#!/usr/bin/env sh
# The bundle's own test suite.
#
# Builds a throwaway repository full of deliberately broken fixtures, runs every
# hook against it, and asserts each one reports the failure it is supposed to.
# This is what catches a scanner that silently passes — the failure mode that
# makes a security hook worse than no hook at all.
#
# Requires: docker, a hook runner, and network access on first run.
set -eu

BUNDLE_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
RUNNER="${RUNNER:-}"

if [ -z "$RUNNER" ]; then
  if command -v pre-commit >/dev/null 2>&1; then
    RUNNER=pre-commit
  elif command -v prek >/dev/null 2>&1; then
    RUNNER=prek
  else
    echo "no hook runner found; set RUNNER=/path/to/pre-commit" >&2
    exit 1
  fi
fi

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT INT TERM

echo "runner:  $RUNNER"
echo "sandbox: $SANDBOX"
echo

# Credential values are generated here, never committed, so this repository holds no
# string that a secret scanner (or GitHub push protection) would flag. The generated
# shapes still match the gitleaks rules, so the hook is tested against a real match.
render_leaky_env() {
  rnd() { LC_ALL=C tr -dc "$1" </dev/urandom | dd bs=1 count="$2" 2>/dev/null; }
  sed \
    -e "s|%%GITHUB_PAT%%|$(rnd 'A-Za-z0-9' 36)|" \
    -e "s|%%AWS_KEY_ID%%|$(rnd 'A-Z0-9' 16)|" \
    -e "s|%%AWS_SECRET%%|$(rnd 'A-Za-z0-9' 40)|" \
    -e "s|%%SLACK_A%%|$(rnd '0-9' 13)|" \
    -e "s|%%SLACK_B%%|$(rnd '0-9' 13)|" \
    -e "s|%%SLACK_C%%|$(rnd 'A-Za-z0-9' 24)|" \
    "$BUNDLE_DIR/demo/leaky.env.tmpl" >"$1"
}

# --- build the sandbox -------------------------------------------------------
# Fixtures are placed at the paths each hook's `files` pattern expects.
cd "$SANDBOX"
git init -q -b verify .
git config user.email verify@example.invalid
git config user.name "verify"

cp "$BUNDLE_DIR/profiles/full.yaml" .pre-commit-config.yaml
cp "$BUNDLE_DIR/.gitleaks.toml" "$BUNDLE_DIR/.gitleaksignore" "$BUNDLE_DIR/.hadolint.yaml" .
render_leaky_env leaky.env
cp "$BUNDLE_DIR/demo/Dockerfile" Dockerfile
cp "$BUNDLE_DIR/demo/insecure.sh" insecure.sh
cp "$BUNDLE_DIR/demo/main.tf" main.tf
mkdir -p k8s .github/workflows
cp "$BUNDLE_DIR/demo/k8s-invalid.yaml" k8s/deployment.yaml
cp "$BUNDLE_DIR/demo/workflow-unsafe.yml" .github/workflows/unsafe.yml
cp "$BUNDLE_DIR/demo/package-lock.json.fixture" package-lock.json
git add -A >/dev/null

PASSES=0
FAILURES=0

report() {
  if [ "$1" = ok ]; then
    PASSES=$((PASSES + 1))
    printf '  ok    %s\n' "$2"
  else
    FAILURES=$((FAILURES + 1))
    printf '  FAIL  %s — %s\n' "$2" "$3"
  fi
}

# A detector that cannot fail on a broken fixture is not detecting anything.
expect_hook_fails() {
  hook="$1"
  shift
  if "$RUNNER" run "$hook" --all-files "$@" >/dev/null 2>&1; then
    report bad "$hook" "passed on a fixture it should have rejected"
  else
    report ok "$hook"
  fi
}

expect_hook_passes() {
  hook="$1"
  shift
  if "$RUNNER" run "$hook" --all-files "$@" >/dev/null 2>&1; then
    report ok "$hook"
  else
    report bad "$hook" "failed on input it should have accepted"
  fi
}

echo "hooks that must reject the fixtures:"
expect_hook_fails gitleaks
expect_hook_fails hadolint
expect_hook_fails shellcheck
expect_hook_fails terraform-fmt
expect_hook_fails trivy-config
expect_hook_fails checkov
expect_hook_fails kubeconform
expect_hook_fails zizmor
expect_hook_fails actionlint
expect_hook_fails osv-scanner --hook-stage pre-push

echo
echo "hooks that must accept the fixtures:"
# The fixture credentials are synthetic, so nothing verifies as live. TruffleHog
# passing here is the correct result and proves the hook runs without erroring.
expect_hook_passes trufflehog --hook-stage pre-push

echo
echo "commit message rule:"
printf 'add some stuff\n' >"$SANDBOX/msg-bad"
printf 'feat(hooks): add gitleaks container hook\n' >"$SANDBOX/msg-good"
if "$RUNNER" run conventional-commit --hook-stage commit-msg \
  --commit-msg-filename "$SANDBOX/msg-bad" >/dev/null 2>&1; then
  report bad conventional-commit "accepted a non-conventional message"
else
  report ok "conventional-commit rejects 'add some stuff'"
fi
if "$RUNNER" run conventional-commit --hook-stage commit-msg \
  --commit-msg-filename "$SANDBOX/msg-good" >/dev/null 2>&1; then
  report ok "conventional-commit accepts 'feat(hooks): ...'"
else
  report bad conventional-commit "rejected a valid conventional message"
fi

echo
echo "-------------------------------------------"
printf '%s checks passed, %s failed\n' "$PASSES" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
