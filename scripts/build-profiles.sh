#!/usr/bin/env sh
# Assembles profiles/*.yaml from profiles/parts/ so the three profiles cannot drift.
# Usage: scripts/build-profiles.sh [--check]
set -eu

cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

render() {
  cat <<'EOF'
# ---------------------------------------------------------------------------
# GENERATED FILE - do not edit.
# Source: profiles/parts/*.yaml   Build: scripts/build-profiles.sh
# ---------------------------------------------------------------------------
EOF
  for part in "$@"; do
    cat "profiles/parts/$part"
  done
}

build() {
  out="$1"
  shift
  if [ "$CHECK" -eq 1 ]; then
    if ! render "$@" | diff -u "$out" - >/dev/null 2>&1; then
      echo "drift: $out is out of date; run scripts/build-profiles.sh" >&2
      render "$@" | diff -u "$out" - >&2 || true
      return 1
    fi
    echo "ok: $out"
  else
    render "$@" >"$out"
    echo "built: $out"
  fi
}

rc=0
build profiles/core.yaml \
  00-header.yaml 10-secrets.yaml 20-core.yaml 90-hygiene.yaml || rc=1
build profiles/iac.yaml \
  00-header.yaml 10-secrets.yaml 20-core.yaml 50-iac.yaml 90-hygiene.yaml || rc=1
build profiles/full.yaml \
  00-header.yaml 10-secrets.yaml 20-core.yaml 50-iac.yaml 60-supply-chain.yaml 90-hygiene.yaml || rc=1

# This repository runs the full profile on itself, minus demo/, whose fixtures are
# broken on purpose and are exercised by scripts/verify.sh in a sandbox instead.
self_config() {
  render 00-header.yaml 10-secrets.yaml 20-core.yaml 50-iac.yaml \
    60-supply-chain.yaml 90-hygiene.yaml |
    awk '{ print }
         /^fail_fast:/ {
           print ""
           print "# demo/ holds deliberately broken fixtures; scripts/verify.sh runs the"
           print "# hooks against them in a sandbox, so they are skipped here."
           print "exclude: ^demo/"
         }'
}
if [ "$CHECK" -eq 1 ]; then
  if self_config | diff -u .pre-commit-config.yaml - >/dev/null 2>&1; then
    echo "ok: .pre-commit-config.yaml"
  else
    echo "drift: .pre-commit-config.yaml is out of date; run scripts/build-profiles.sh" >&2
    rc=1
  fi
else
  self_config >.pre-commit-config.yaml
  echo "built: .pre-commit-config.yaml"
fi

exit "$rc"
