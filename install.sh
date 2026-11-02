#!/usr/bin/env bash
# Installs NtfyMac.app into ~/Applications and links the CLI into ~/.local/bin.
# The download is checked against the release's SHA256SUMS before anything is extracted, and a
# failed check installs nothing. Rerun to update.
#
# Environment:
#   NTFY_MAC_VERSION    version to install (default: the latest GitHub release)
#   NTFY_MAC_APP_DIR    where NtfyMac.app goes (default: ~/Applications)
#   NTFY_MAC_BIN_DIR    where the ntfy-mac link goes (default: ~/.local/bin)
#   NTFY_MAC_NO_LAUNCH  set to 1 to skip opening the app
#   NTFY_MAC_BASE_URL   directory URL holding the release files (tests; replaces the GitHub download URL)
set -euo pipefail

REPO="jkrumm/ntfy-mac"
APP_DIR="${NTFY_MAC_APP_DIR:-$HOME/Applications}"
BIN_DIR="${NTFY_MAC_BIN_DIR:-$HOME/.local/bin}"
SEMVER='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

fail() {
  echo "ntfy-mac install: $*" >&2
  exit 1
}

# ── Platform ──────────────────────────────────────────────────────────────────

[[ "$(uname -m)" == "arm64" ]] || fail "requires Apple Silicon (arm64), got $(uname -m)"
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$macos_major" -ge 15 ]] || fail "requires macOS 15 or later, got $(sw_vers -productVersion)"

# ── Version ───────────────────────────────────────────────────────────────────

version="${NTFY_MAC_VERSION:-}"
if [[ -z "$version" ]]; then
  echo "Looking up the latest release..."
  tag="$(curl -fsSL --proto '=https' --tlsv1.2 "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -nE 's/.*"tag_name": *"([^"]*)".*/\1/p' | head -1)"
  [[ -n "$tag" ]] || fail "could not read the latest release"
  version="$tag"
fi
version="${version#v}"
[[ "$version" =~ $SEMVER ]] || fail "not a version: $version"

archive="ntfy-mac-$version-arm64.tar.gz"
base_url="${NTFY_MAC_BASE_URL:-https://github.com/$REPO/releases/download/v$version}"
curl_opts=(-fsSL)
[[ -n "${NTFY_MAC_BASE_URL:-}" ]] || curl_opts+=(--proto '=https' --tlsv1.2)

work="$(mktemp -d)"
cleanup() {
  rm -rf "$work"
  [[ -z "${stage:-}" ]] || rm -rf "$stage"
}
trap cleanup EXIT

# ── Download and verify ───────────────────────────────────────────────────────

echo "Downloading ntfy-mac $version (arm64)..."
mkdir "$work/download" "$work/extract"
curl "${curl_opts[@]}" "$base_url/$archive" -o "$work/download/$archive" || fail "download of $archive failed"
curl "${curl_opts[@]}" "$base_url/SHA256SUMS" -o "$work/download/SHA256SUMS" || fail "download of SHA256SUMS failed"

listed="$(awk -v f="$archive" '$2 == f' "$work/download/SHA256SUMS" | wc -l | tr -d ' ')"
[[ "$listed" == "1" ]] || fail "SHA256SUMS must list $archive exactly once (found $listed)"
(cd "$work/download" && shasum -a 256 -c --ignore-missing --strict SHA256SUMS >/dev/null) \
  || fail "checksum mismatch for $archive; nothing was installed"

# ── Extract ───────────────────────────────────────────────────────────────────

entries="$(tar -tzf "$work/download/$archive")" || fail "cannot read $archive"
while IFS= read -r entry; do
  [[ "$entry" =~ ^(\./)?(NtfyMac\.app(/.*)?|LICENSE)$ && ! "$entry" =~ (^|/)\.\.(/|$) ]] \
    || fail "unexpected entry in $archive: $entry"
done <<<"$entries"
tar -xzf "$work/download/$archive" -C "$work/extract"
cli_in_bundle="$work/extract/NtfyMac.app/Contents/MacOS/ntfy-mac"
[[ -x "$cli_in_bundle" ]] || fail "$archive has no NtfyMac.app/Contents/MacOS/ntfy-mac"

# ── Install ───────────────────────────────────────────────────────────────────

mkdir -p "$APP_DIR" "$BIN_DIR"
target="$APP_DIR/NtfyMac.app"
stage="$APP_DIR/.NtfyMac.app.new.$$"
ditto "$work/extract/NtfyMac.app" "$stage"
if [[ -e "$target" ]]; then
  old="$APP_DIR/.NtfyMac.app.old.$$"
  mv "$target" "$old"
  mv "$stage" "$target" || { mv "$old" "$target"; fail "could not replace $target"; }
  rm -rf "$old"
else
  mv "$stage" "$target"
fi
stage=""

cli="$target/Contents/MacOS/ntfy-mac"
ln -sfn "$cli" "$BIN_DIR/ntfy-mac"
echo "Installed $target"
echo "Linked $BIN_DIR/ntfy-mac"

# ── Migrate from 1.x ──────────────────────────────────────────────────────────

"$cli" migrate || fail "ntfy-mac migrate failed; the app is installed, rerun this script or run '$BIN_DIR/ntfy-mac migrate'"

# ── Done ──────────────────────────────────────────────────────────────────────

if [[ "${NTFY_MAC_NO_LAUNCH:-}" != "1" ]]; then
  open "$target"
  echo "If ntfy-mac was already running, quit it from the menu bar and open it again to load $version."
fi

echo ""
echo "ntfy-mac $version installed. Next: ntfy-mac setup"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo ""
    echo "$BIN_DIR is not on your PATH. Add it:"
    echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    ;;
esac
