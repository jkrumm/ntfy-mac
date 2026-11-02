#!/usr/bin/env bash
# Installs NtfyMac.app into ~/Applications and links the CLI into ~/.local/bin.
# The download is checked against the release's SHA256SUMS before anything is extracted, and a
# failed check installs nothing; so does an extracted bundle with a bad code signature or a
# symbolic link that leaves the bundle. Rerun to update.
#
# Environment:
#   NTFY_MAC_VERSION    version to install (default: the latest GitHub release)
#   NTFY_MAC_APP_DIR    where NtfyMac.app goes (default: ~/Applications)
#   NTFY_MAC_BIN_DIR    where the ntfy-mac link goes (default: ~/.local/bin)
#   NTFY_MAC_NO_LAUNCH  set to 1 to skip opening the app
#   NTFY_MAC_BASE_URL   directory URL holding the release files (tests; replaces the GitHub download
#                       URL; only file://, http://127.0.0.1 and http://localhost are accepted)
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
if [[ -n "${NTFY_MAC_BASE_URL:-}" ]]; then
  # A stray variable must not downgrade the https and TLS 1.2 pins below.
  case "$NTFY_MAC_BASE_URL" in
    file://* | http://127.0.0.1 | http://127.0.0.1[:/]* | http://localhost | http://localhost[:/]*) ;;
    *) fail "NTFY_MAC_BASE_URL must be a file:// or local http:// URL (got $NTFY_MAC_BASE_URL); unset it to install from GitHub" ;;
  esac
else
  curl_opts+=(--proto '=https' --tlsv1.2)
fi

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

# A symbolic link that resolves outside the bundle (or nowhere) is refused before it can be installed.
extracted="$work/extract/NtfyMac.app"
bundle_root="$(realpath "$extracted")"
while IFS= read -r -d '' link; do
  resolved="$(realpath "$link" 2>/dev/null)" || fail "symbolic link $link in $archive does not resolve; nothing was installed"
  case "$resolved" in
    "$bundle_root" | "$bundle_root"/*) ;;
    *) fail "symbolic link ${link#"$extracted"/} in $archive points outside the app; nothing was installed" ;;
  esac
done < <(find "$extracted" -type l -print0)

codesign --verify --deep --strict "$extracted" 2>/dev/null \
  || fail "the code signature of the extracted app does not verify; nothing was installed"

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
echo "Installed $target"

# ── Migrate from 1.x ──────────────────────────────────────────────────────────

# Before the link is replaced: a running 1.x daemon is recognised by its executable path, which is
# the old $BIN_DIR/ntfy-mac. Run through the bundle's own path, not the link. A failure is shown but
# does not undo the install.
"$cli" migrate || echo "ntfy-mac install: warning: 'migrate' failed; the app is installed. Run '$cli migrate' to retry." >&2

ln -sfn "$cli" "$BIN_DIR/ntfy-mac"
echo "Linked $BIN_DIR/ntfy-mac"

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
