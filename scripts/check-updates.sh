#!/usr/bin/env sh
# Reports newer upstream releases for the container images pinned in the profiles.
#
# `pre-commit autoupdate` cannot help here: it bumps `rev:` on hook repositories,
# and this bundle pins images instead. This is the replacement.
#
# Set GITHUB_TOKEN to raise the anonymous API rate limit.
set -eu

BUNDLE_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
PROFILE="$BUNDLE_DIR/profiles/full.yaml"

# image reference prefix <space> upstream GitHub repository
MAPPING=$(
  cat <<'EOF'
ghcr.io/gitleaks/gitleaks gitleaks/gitleaks
trufflesecurity/trufflehog trufflesecurity/trufflehog
hadolint/hadolint hadolint/hadolint
koalaman/shellcheck koalaman/shellcheck
mvdan/shfmt mvdan/sh
hashicorp/terraform hashicorp/terraform
aquasec/trivy aquasecurity/trivy
bridgecrew/checkov bridgecrewio/checkov
ghcr.io/yannh/kubeconform yannh/kubeconform
ghcr.io/zizmorcore/zizmor zizmorcore/zizmor
rhysd/actionlint rhysd/actionlint
ghcr.io/google/osv-scanner google/osv-scanner
EOF
)

auth_header() {
  [ -n "${GITHUB_TOKEN:-}" ] && printf 'Authorization: Bearer %s' "$GITHUB_TOKEN"
}

latest_release() {
  url="https://api.github.com/repos/$1/releases/latest"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "$(auth_header)" "$url" 2>/dev/null
  else
    curl -fsSL "$url" 2>/dev/null
  fi | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
}

strip_v() { printf '%s' "${1#v}"; }

printf '%-32s %-12s %-12s %s\n' IMAGE PINNED LATEST STATUS
printf '%-32s %-12s %-12s %s\n' '------' '------' '------' '------'

outdated=0
echo "$MAPPING" | while read -r image repo; do
  [ -n "$image" ] || continue
  pinned=$(grep -oE "${image}:[A-Za-z0-9._-]+" "$PROFILE" | head -1 | sed "s|^${image}:||")
  [ -n "$pinned" ] || continue

  latest=$(latest_release "$repo")
  if [ -z "$latest" ]; then
    printf '%-32s %-12s %-12s %s\n' "$image" "$pinned" '?' 'lookup failed'
    continue
  fi

  if [ "$(strip_v "$pinned")" = "$(strip_v "$latest")" ]; then
    printf '%-32s %-12s %-12s %s\n' "$image" "$pinned" "$latest" 'up to date'
  else
    printf '%-32s %-12s %-12s %s\n' "$image" "$pinned" "$latest" 'UPDATE AVAILABLE'
    outdated=$((outdated + 1))
  fi
done

cat <<EOF

To upgrade: edit the pin in profiles/parts/*.yaml, run scripts/build-profiles.sh,
then scripts/verify.sh to confirm the new image still behaves the same way.
EOF
