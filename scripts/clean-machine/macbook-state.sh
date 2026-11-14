#!/usr/bin/env bash
# macbook-state.sh — a read-only snapshot of what an update must keep, for a real Mac where the notification
# permission is allowed (a clean-machine guest can never grant it; docs/clean-machine.md). Run it before and after an
# update or a Homebrew move and compare the two outputs. It changes nothing and prints no token or team id.
set -uo pipefail

cli="${NTFY_MAC_CLI:-$(command -v ntfy-mac || true)}"
[[ -x "$cli" ]] || {
  echo "ntfy-mac is not on PATH (set NTFY_MAC_CLI=<path to the ntfy-mac binary>)" >&2
  exit 2
}

status="$("$cli" status --json 2>/dev/null)"
echo "macOS:       $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
for app in "$HOME/Applications/NtfyMac.app" /Applications/NtfyMac.app; do
  [[ -d "$app" ]] || continue
  echo "copy:        $app  version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" \
    " quarantine=$(xattr -p com.apple.quarantine "$app" 2>/dev/null | cut -d';' -f1 || true)" \
    " gatekeeper=$(spctl --assess --type execute --verbose=4 "$app" 2>&1 | sed -n 's/.*source=//p')"
done
echo "channel:     $("$cli" doctor --json 2>/dev/null | jq -r '.installChannel')"
echo "running:     $(pgrep -fl 'NtfyMac.app/Contents/MacOS/NtfyMac' | sed 's/^[0-9]* //' | tr '\n' ' ')"
echo "permission:  $(jq -r 'if .permission.usable then "ALLOWED" else (.permission.problems[0].code // "unknown") end' <<<"$status")"
echo "history:     $(jq -r '.history.total' <<<"$status") messages, connection $(jq -r '.connection' <<<"$status")"
echo "config sha:  $(shasum -a 256 "$HOME/.config/ntfy-mac/config.json" 2>/dev/null | cut -c1-12)"
echo "team pin sha: $(shasum -a 256 "$HOME/Library/Application Support/ntfy-mac/team-pin" 2>/dev/null | cut -c1-12)"
echo "keychain:    $(security find-generic-password -s com.jkrumm.ntfy-mac >/dev/null 2>&1 && echo token present || echo no token)"
