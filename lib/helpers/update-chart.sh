#!/usr/bin/env bash
set -euo pipefail

NIX_FLAGS=("--extra-experimental-features" "nix-command")

target="$CHARTS_DIR/$CHART_SUBPATH/default.nix"

if [[ ! -f "$target" ]]; then
  echo "error: $target not found (set CHARTS_DIR to your charts dir)" >&2
  exit 1
fi

CHART_JSON="$(nix "${NIX_FLAGS[@]}" eval -f "$target" --json)"

# The freeze setting in the local file should always take
# precedence over what the derivation was built with.
CHART_LOCAL_FREEZE="$(echo "$CHART_JSON" | yq -r .freeze)"
if [[ "$CHART_LOCAL_FREEZE" == "true" ]]; then
  echo "warning: $target sets \`freeze = true;\` locally, skipping update"
  exit 0
fi

# The versionConstraint set in the local file should always take
# precedence over what the derivation was built with.
CHART_LOCAL_VERSION_CONSTRAINT="$(echo "$CHART_JSON" | yq -r .versionConstraint)"
if [[ "$CHART_LOCAL_VERSION_CONSTRAINT" != "null" ]]; then
  CHART_VERSION_CONSTRAINT="$CHART_LOCAL_VERSION_CONSTRAINT"
fi

# Resolve latest allowed version
if [[ -n "${CHART_VERSION_CONSTRAINT:-}" ]]; then
  version=$(helm show chart "$CHART_NAME" --repo "$CHART_REPO" \
            --version "$CHART_VERSION_CONSTRAINT" | yq '.version')
else
  version=$(helm show chart "$CHART_NAME" --repo "$CHART_REPO" | yq '.version')
fi

# Pull + predictable hash
tmp=$(mktemp -d)
helm pull "$CHART_NAME" --repo "$CHART_REPO" --version "$version" \
      --destination "$tmp" --untar
hash=$(nix "${NIX_FLAGS[@]}" hash path --type sha256 --sri "$tmp/$CHART_NAME")
rm -rf "$tmp"

# Check if any update is required
CHART_LOCAL_VERSION="$(echo "$CHART_JSON" | yq -r .version)"
CHART_LOCAL_HASH="$(echo "$CHART_JSON" | yq -r .chartHash)"
if [[ "$CHART_LOCAL_VERSION" == "$version" && "$CHART_LOCAL_HASH" == "$hash" ]]; then
  # No need to continue
  echo "$target is up to date"
  exit 0
fi

# Rewrite the working-tree file in place (preserves freeze/constraint/comments)
sed -i -E \
 -e 's|^([[:space:]]*)version[[:space:]]*=[[:space:]]*"[^"]*"|\1version = "'"$version"'"|' \
 -e 's|^([[:space:]]*)chartHash[[:space:]]*=[[:space:]]*"[^"]*"|\1chartHash = "'"$hash"'"|' \
 "$target"

# Fallback to full template
CHART_JSON="$(nix "${NIX_FLAGS[@]}" eval -f "$target" --json)"
CHART_LOCAL_VERSION="$(echo "$CHART_JSON" | yq -r .version)"
CHART_LOCAL_HASH="$(echo "$CHART_JSON" | yq -r .chartHash)"
if [[ "$CHART_LOCAL_VERSION" != "$version" || "$CHART_LOCAL_HASH" != "$hash" ]]; then
  {
    echo "{"
    echo "  repo = \"$CHART_REPO\";"
    echo "  chart = \"$CHART_NAME\";"
    echo "  version = \"$version\";"
    echo "  chartHash = \"$hash\";"
    if [[ -n "${CHART_VERSION_CONSTRAINT}" ]]; then
      echo "  versionConstraint = \"$CHART_VERSION_CONSTRAINT\";"
    fi
    echo "}"
  } > "$target"
fi

echo "updated $target to $version ($hash)"
