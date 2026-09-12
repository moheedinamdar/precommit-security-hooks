#!/usr/bin/env sh
# On-demand deep scans. The git hooks only see what you are committing; these
# commands scan the whole repository, including history.
#
#   scripts/scan.sh secrets    gitleaks over full git history
#   scripts/scan.sh verified   trufflehog over full history, live credentials only
#   scripts/scan.sh baseline   record current findings as the accepted baseline
#   scripts/scan.sh all        secrets + verified
set -eu

BUNDLE_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
REPO="$PWD"

# Image pins are read from the profile so there is exactly one place to bump them.
image_for() {
  grep -oE "$1:[A-Za-z0-9._-]+" "$BUNDLE_DIR/profiles/full.yaml" | head -1
}
GITLEAKS_IMAGE="$(image_for 'ghcr\.io/gitleaks/gitleaks')"
TRUFFLEHOG_IMAGE="$(image_for 'trufflesecurity/trufflehog')"

# Running as the host uid keeps report files writable, but then git inside the
# container refuses the bind mount ("dubious ownership") and gitleaks silently
# falls back to --no-index and exits 0. GIT_CONFIG_* fixes that without touching
# the caller's git config.
run_container() {
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e GIT_CONFIG_COUNT=1 \
    -e GIT_CONFIG_KEY_0=safe.directory \
    -e GIT_CONFIG_VALUE_0='*' \
    -v "$REPO:/src" -w /src "$@"
}

scan_secrets() {
  echo "== gitleaks · full history =="
  baseline_arg=""
  [ -f "$REPO/.gitleaks-baseline.json" ] && baseline_arg="--baseline-path=.gitleaks-baseline.json"
  # shellcheck disable=SC2086 # deliberate word splitting of the optional flag
  run_container "$GITLEAKS_IMAGE" git . --redact --no-banner $baseline_arg
}

scan_verified() {
  echo "== trufflehog · full history, verified credentials =="
  run_container "$TRUFFLEHOG_IMAGE" \
    git file:///src --results=verified,unknown --fail --no-update
}

make_baseline() {
  echo "== gitleaks · writing .gitleaks-baseline.json =="
  run_container "$GITLEAKS_IMAGE" \
    dir . --no-banner --exit-code 0 --report-path .gitleaks-baseline.json
  cat <<'EOF'

Baseline written to .gitleaks-baseline.json.

Findings recorded there are excluded from `scan.sh secrets` from now on. That is
an acknowledgement, not a fix: if any of them was ever a real credential, ROTATE
IT. It stays in git history whatever this file says.

Commit the baseline so the whole team shares the same starting point, and shrink
it over time rather than regenerating it.
EOF
}

case "${1:-all}" in
  secrets)  scan_secrets ;;
  verified) scan_verified ;;
  baseline) make_baseline ;;
  all)      scan_secrets; scan_verified ;;
  *) echo "usage: scan.sh [secrets|verified|baseline|all]" >&2; exit 2 ;;
esac
