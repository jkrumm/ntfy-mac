#!/usr/bin/env bash
# Pinned dev tools for macOS arm64: download, verify SHA-256, cache in .tools/, print the binary path.
# Usage: scripts/tools.sh <swiftlint|periphery>
# Bump a tool by changing its version and checksum below (checksum: `gh release view` asset digest).
set -euo pipefail

SWIFTLINT_VERSION="0.65.1"
SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
SWIFTLINT_SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"

PERIPHERY_VERSION="3.8.0"
PERIPHERY_URL="https://github.com/peripheryapp/periphery/releases/download/${PERIPHERY_VERSION}/periphery-${PERIPHERY_VERSION}.zip"
PERIPHERY_SHA256="07d4e286e31dd79164df39097e0b59f533c94badbe18158464a455ea88a166d7"

tool="${1:?usage: tools.sh <swiftlint|periphery>}"

if [[ "$(uname -s)-$(uname -m)" != "Darwin-arm64" ]]; then
  echo "tools.sh supports macOS arm64 only" >&2
  exit 1
fi

case "$tool" in
  swiftlint | periphery) ;;
  *)
    echo "unknown tool: $tool" >&2
    exit 1
    ;;
esac

upper=$(echo "$tool" | tr '[:lower:]' '[:upper:]')
version_var="${upper}_VERSION"
url_var="${upper}_URL"
sha_var="${upper}_SHA256"
version="${!version_var}"
url="${!url_var}"
sha="${!sha_var}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$root/.tools/$tool-$version"
bin="$dest/$tool"

if [[ -x "$bin" ]]; then
  echo "$bin"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "fetching $tool $version" >&2
curl --fail --silent --show-error --location "$url" --output "$work/archive.zip"
actual=$(shasum -a 256 "$work/archive.zip" | cut -d' ' -f1)
if [[ "$actual" != "$sha" ]]; then
  echo "checksum mismatch for $tool $version: expected $sha, got $actual" >&2
  exit 1
fi

mkdir -p "$work/out" "$root/.tools"
unzip -q "$work/archive.zip" -d "$work/out"
chmod +x "$work/out/$tool"
rm -rf "$dest"
mv "$work/out" "$dest"
echo "$bin"
