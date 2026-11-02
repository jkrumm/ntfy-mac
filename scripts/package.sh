#!/usr/bin/env bash
# Packages the signed app into dist/: ntfy-mac-<version>-arm64.tar.gz (NtfyMac.app/ and LICENSE at the
# root; the sibling file keeps Homebrew from stripping the lone top-level .app) and SHA256SUMS.
# Build and sign first (`make app`); `make package VERSION=x.y.z` does both.
set -euo pipefail

version="${1:?usage: package.sh <version> [app-path]}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${2:-$root/.build/xcode/Build/Products/Release/NtfyMac.app}"
dist="${DIST_DIR:-$root/dist}"
archive="ntfy-mac-$version-arm64.tar.gz"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "not a semantic version: $version" >&2
  exit 1
fi
[[ -x "$app/Contents/MacOS/ntfy-mac" ]] || { echo "no built app at $app (run make app)" >&2; exit 1; }

built="$("$app/Contents/MacOS/ntfy-mac" version)"
if [[ "$built" != *" $version" ]]; then
  echo "the built CLI says '$built', expected version $version (run scripts/stamp-version.sh first)" >&2
  exit 1
fi
codesign --verify --deep --strict "$app"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto --norsrc --noextattr --noqtn "$app" "$stage/NtfyMac.app"
cp "$root/LICENSE" "$stage/LICENSE"

rm -rf "$dist"
mkdir -p "$dist"
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$dist/$archive" -C "$stage" NtfyMac.app LICENSE

if tar -tzf "$dist/$archive" | grep -Eq '(^|/)\._'; then
  echo "archive contains AppleDouble files" >&2
  exit 1
fi
(cd "$dist" && shasum -a 256 "$archive" >SHA256SUMS && shasum -a 256 -c --strict SHA256SUMS)
echo "packaged $dist/$archive"
