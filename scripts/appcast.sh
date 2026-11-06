#!/usr/bin/env bash
# Builds the Sparkle appcast for one release zip. Usage: scripts/appcast.sh <zip> <version> <build> <out-appcast.xml>
#   <zip>      NtfyMac-<version>.zip (ditto of the stapled app; generate_appcast wants the app alone in the archive)
#   <version>  the release version (full semver; names the download URL)
#   <build>    the app's CFBundleVersion, which Sparkle compares (sparkle:version)
# The EdDSA key is SPARKLE_ED_PRIVATE_KEY (CI; written to a 0600 temp file) or SPARKLE_KEY_FILE (default
# ~/.local/state/apple-developer/sparkle-ntfy-mac-ed25519.key on the mini). generate_appcast and sign_update get
# --ed-key-file: the keychain path hangs headless. The tools are the pinned ones from scripts/tools.sh (SPARKLE_BIN
# overrides the directory). The item is checked before the script succeeds: version, enclosure URL, edSignature, and
# sign_update --verify against the zip.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
zip="${1:?usage: appcast.sh <zip> <version> <build> <out-appcast.xml>}"
version="${2:?version}"
build="${3:?build}"
out="${4:?output path}"
repo="${RELEASE_REPO:-jkrumm/ntfy-mac}"

fail() {
  echo "appcast: $*" >&2
  exit 1
}

[[ -f "$zip" ]] || fail "no zip at $zip"
bin="${SPARKLE_BIN:-$(dirname "$("$root/scripts/tools.sh" sparkle)")}"
[[ -x "$bin/generate_appcast" && -x "$bin/sign_update" ]] || fail "Sparkle tools not found in $bin"

work="$(mktemp -d)"
key_file="${SPARKLE_KEY_FILE:-$HOME/.local/state/apple-developer/sparkle-ntfy-mac-ed25519.key}"
trap 'rm -rf "$work"' EXIT
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  key_file="$work/ed.key"
  (umask 077 && printf '%s' "$SPARKLE_ED_PRIVATE_KEY" >"$key_file")
fi
[[ -r "$key_file" ]] || fail "no Sparkle EdDSA key: set SPARKLE_ED_PRIVATE_KEY, or SPARKLE_KEY_FILE ($key_file is missing)"

# Only the zip goes in: the directory is scanned for every archive and a stale appcast is merged.
mkdir "$work/feed"
cp "$zip" "$work/feed/"
"$bin/generate_appcast" --ed-key-file "$key_file" \
  --download-url-prefix "https://github.com/$repo/releases/download/v$version/" "$work/feed" >/dev/null
feed="$work/feed/appcast.xml"
[[ -f "$feed" ]] || fail "generate_appcast wrote no appcast.xml"

name="$(basename "$zip")"
signature="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$feed" | head -n 1)"
[[ -n "$signature" ]] || fail "the appcast item has no sparkle:edSignature"
grep -q "<sparkle:version>$build</sparkle:version>" "$feed" || fail "sparkle:version is not $build"
grep -q "url=\"https://github.com/$repo/releases/download/v$version/$name\"" "$feed" \
  || fail "the enclosure url is not the release asset $name"
"$bin/sign_update" --verify --ed-key-file "$key_file" "$zip" "$signature" >/dev/null \
  || fail "sign_update --verify rejects the signature for $name"

cp "$feed" "$out"
echo "appcast: $out (sparkle:version $build, edSignature verifies against $name)"
