#!/usr/bin/env sh
# Install this security hook bundle into a git repository.
#
#   cd /path/to/your/repo
#   /path/to/precommit-security-hooks/install.sh --profile core
#
# Nothing is installed on the machine except the hook runner itself; every scanner
# runs from a pinned official container image.
set -eu

BUNDLE_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROFILE=core
RUNNER=auto
TARGET="$PWD"
FORCE=0
CONFIG_ONLY=0

usage() {
  cat <<EOF
Usage: install.sh [options]

  --profile core|iac|full   Hook set to install (default: core)
                              core - secrets, containers, shell, commit messages
                              iac  - core + Terraform, Trivy, Checkov, kubeconform
                              full - iac + zizmor, actionlint, osv-scanner, shfmt
  --runner auto|pre-commit|prek
                            Hook runner to wire up (default: auto-detect)
  --target DIR              Repository to install into (default: current directory)
  --config-only             Write config files, do not install git hooks
  --force                   Overwrite an existing .pre-commit-config.yaml
  -h, --help                Show this message
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
    --profile=*) PROFILE="${1#*=}"; shift ;;
    --runner) RUNNER="${2:?--runner needs a value}"; shift 2 ;;
    --runner=*) RUNNER="${1#*=}"; shift ;;
    --target) TARGET="${2:?--target needs a value}"; shift 2 ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    --config-only) CONFIG_ONLY=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$PROFILE" in
  core|iac|full) ;;
  *) echo "invalid --profile '$PROFILE' (expected core, iac or full)" >&2; exit 2 ;;
esac

[ -f "$BUNDLE_DIR/profiles/$PROFILE.yaml" ] ||
  { echo "missing $BUNDLE_DIR/profiles/$PROFILE.yaml" >&2; exit 1; }

TARGET="$(CDPATH='' cd -- "$TARGET" && pwd)"
[ -d "$TARGET/.git" ] ||
  { echo "$TARGET is not a git repository (run 'git init' first)" >&2; exit 1; }

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH." >&2
  echo "Every scanner in this bundle runs from a container; install Docker first." >&2
  exit 1
fi

if [ "$RUNNER" = auto ]; then
  if command -v prek >/dev/null 2>&1; then
    RUNNER=prek
  elif command -v pre-commit >/dev/null 2>&1; then
    RUNNER=pre-commit
  else
    cat >&2 <<'EOF'
No hook runner found. Install one of:

  prek        (single binary, no Python)
              curl -LsSf https://prek.j178.dev/install.sh | sh
  pre-commit  (Python)
              pipx install pre-commit

Then re-run this script.
EOF
    exit 1
  fi
fi

command -v "$RUNNER" >/dev/null 2>&1 ||
  { echo "requested runner '$RUNNER' is not on PATH" >&2; exit 1; }

# --- config files ------------------------------------------------------------
CONFIG="$TARGET/.pre-commit-config.yaml"
if [ -e "$CONFIG" ] && [ "$FORCE" -eq 0 ]; then
  echo "$CONFIG already exists. Re-run with --force to overwrite, or merge by hand:" >&2
  echo "  diff -u '$CONFIG' '$BUNDLE_DIR/profiles/$PROFILE.yaml'" >&2
  exit 1
fi
cp "$BUNDLE_DIR/profiles/$PROFILE.yaml" "$CONFIG"
echo "wrote  .pre-commit-config.yaml  (profile: $PROFILE)"

# Tool configs are never overwritten: a repo's existing tuning wins.
for f in .gitleaks.toml .gitleaksignore .hadolint.yaml; do
  if [ -e "$TARGET/$f" ]; then
    echo "kept   $f  (already present)"
  else
    cp "$BUNDLE_DIR/$f" "$TARGET/$f"
    echo "wrote  $f"
  fi
done

if [ "$CONFIG_ONLY" -eq 1 ]; then
  echo "done (--config-only): no git hooks installed."
  exit 0
fi

# --- git hooks ---------------------------------------------------------------
cd "$TARGET"
"$RUNNER" install --install-hooks \
  --hook-type pre-commit --hook-type commit-msg --hook-type pre-push

cat <<EOF

Installed with $RUNNER.

Next steps
  1. First full pass (pulls the container images, so it is the slow one):
       $RUNNER run --all-files
  2. Accept anything pre-existing that is genuinely not a secret:
       $BUNDLE_DIR/scripts/scan.sh baseline
  3. Commit .pre-commit-config.yaml and the config files so your team inherits them.
EOF
