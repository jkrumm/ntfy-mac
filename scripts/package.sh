#!/usr/bin/env bash
# Packages the signed, notarized and stapled app into dist/:
#   ntfy-mac-<version>-arm64.tar.gz  NtfyMac.app/ and LICENSE at the root (the sibling file keeps Homebrew from
#                                    stripping the lone top-level .app); install.sh uses it
#   NtfyMac-<version>.zip            the app alone, the Sparkle enclosure
#   appcast.xml                      the Sparkle feed item for the zip (scripts/appcast.sh)
#   SHA256SUMS                       every file above
# Build and sign first (`SIGN_IDENTITY=developer-id NOTARIZE=1 make app`); `make package VERSION=x.y.z` does both.
# The app must verify as Developer ID signed, notarized and stapled (scripts/verify-signature.sh --release), and the
# staple ticket must survive both archives: each is extracted and validated again. ALLOW_ADHOC=1 is for local
# packaging tests only: it accepts an ad-hoc app and writes no appcast.
set -euo pipefail

version="${1:?usage: package.sh <version> [app-path]}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${2:-$root/.build/xcode/Build/Products/Release/NtfyMac.app}"
dist="${DIST_DIR:-$root/dist}"
archive="ntfy-mac-$version-arm64.tar.gz"
zip="NtfyMac-$version.zip"
adhoc="${ALLOW_ADHOC:-0}"

fail() {
  echo "package: $*" >&2
  exit 1
}

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "not a semantic version: $version"
[[ -x "$app/Contents/MacOS/ntfy-mac" ]] || fail "no built app at $app (run make app)"

built="$("$app/Contents/MacOS/ntfy-mac" version)"
[[ "$built" == *" $version" ]] || fail "the built CLI says '$built', expected version $version (run scripts/stamp-version.sh first)"

if [[ "$adhoc" == 1 ]]; then
  echo "package: ALLOW_ADHOC=1, accepting an ad-hoc app and skipping the appcast (never for a release)" >&2
  codesign --verify --deep --strict "$app"
else
  "$root/scripts/verify-signature.sh" "$app" --release \
    || fail "the app is not Developer ID signed, notarized and stapled: SIGN_IDENTITY=developer-id NOTARIZE=1 make app"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto --norsrc --noextattr --noqtn "$app" "$stage/NtfyMac.app"
cp "$root/LICENSE" "$stage/LICENSE"

rm -rf "$dist"
mkdir -p "$dist"
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$dist/$archive" -C "$stage" NtfyMac.app LICENSE
ditto -c -k --sequesterRsrc --keepParent "$stage/NtfyMac.app" "$dist/$zip"

if tar -tzf "$dist/$archive" | grep -Eq '(^|/)\._'; then
  fail "archive contains AppleDouble files"
fi

# Both archives must still validate after extraction: a ticket lost in packaging would fail only on a user's Mac.
if [[ "$adhoc" != 1 ]]; then
  mkdir "$stage/check-tar" "$stage/check-zip"
  tar -xzf "$dist/$archive" -C "$stage/check-tar"
  ditto -x -k "$dist/$zip" "$stage/check-zip"
  xcrun stapler validate "$stage/check-tar/NtfyMac.app" >/dev/null || fail "$archive does not keep the staple ticket"
  xcrun stapler validate "$stage/check-zip/NtfyMac.app" >/dev/null || fail "$zip does not keep the staple ticket"
  "$root/scripts/verify-signature.sh" "$stage/check-tar/NtfyMac.app" --release >/dev/null || fail "the extracted tarball app does not verify"
  "$root/scripts/verify-signature.sh" "$stage/check-zip/NtfyMac.app" --release >/dev/null || fail "the extracted zip app does not verify"
  echo "package: tarball and zip validate after extraction"

  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
  "$root/scripts/appcast.sh" "$dist/$zip" "$version" "$build" "$dist/appcast.xml"
fi

files=("$archive" "$zip")
[[ "$adhoc" == 1 ]] || files+=(appcast.xml)
(cd "$dist" && shasum -a 256 "${files[@]}" >SHA256SUMS && shasum -a 256 -c --strict SHA256SUMS)
echo "packaged $dist: ${files[*]}"
