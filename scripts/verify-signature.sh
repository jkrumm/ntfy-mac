#!/usr/bin/env bash
# Verifies the signature of NtfyMac.app. Usage: scripts/verify-signature.sh <app> [--developer-id | --release]
#   (none)          codesign --verify --deep --strict; when the app is Developer ID signed, the full check below
#   --developer-id  the app must be Developer ID signed: team, Hardened Runtime, secure timestamp, Authority, no
#                   get-task-allow, no app-sandbox, and the same for the bundled CLI and Sparkle's helpers
#   --release       --developer-id plus a stapled ticket (stapler validate) and Gatekeeper (spctl: Notarized Developer ID)
# The expected team comes from APPLE_TEAM_ID or secrets-run (scripts/apple-credentials.sh). Any failure exits non-zero.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:?usage: verify-signature.sh <app> [--developer-id|--release]}"
mode="${2:-}"
case "$mode" in
  "" | --developer-id | --release) ;;
  *) echo "unknown option: $mode" >&2; exit 2 ;;
esac
[[ -d "$app" ]] || { echo "no app at $app" >&2; exit 1; }

failed=0
problem() {
  echo "verify-signature: $*" >&2
  failed=1
}

codesign --verify --deep --strict "$app" || { echo "verify-signature: codesign --verify failed for $app" >&2; exit 1; }

info="$(codesign -dvv "$app" 2>&1)"
adhoc=0
grep -q '^Signature=adhoc' <<<"$info" && adhoc=1
if [[ "$adhoc" == 1 && -z "$mode" ]]; then
  echo "verify-signature: ad-hoc signature verifies (not a release build)"
  exit 0
fi

# shellcheck source=scripts/apple-credentials.sh
. "$root/scripts/apple-credentials.sh"
load_team

# check_code <path> <label>: the signature facts every piece of shipped code must have.
check_code() {
  local path="$1" label="$2" i ents
  i="$(codesign -dvv "$path" 2>&1)" || { problem "$label is not signed"; return; }
  ents="$(codesign -d --entitlements - --xml "$path" 2>/dev/null || true)"
  grep -q '^Authority=Developer ID Application:' <<<"$i" || problem "$label: Authority is not Developer ID Application"
  grep -q "^TeamIdentifier=$TEAM\$" <<<"$i" || problem "$label: TeamIdentifier is not the expected team"
  grep -Eq 'flags=0x[0-9a-f]+\(.*runtime' <<<"$i" || problem "$label: Hardened Runtime is off"
  grep -q '^Timestamp=' <<<"$i" || problem "$label: no secure timestamp"
  ! grep -q 'com.apple.security.get-task-allow' <<<"$ents" || problem "$label: get-task-allow is set (notarization refuses it)"
  ! grep -q 'com.apple.security.app-sandbox' <<<"$ents" || problem "$label: the code is sandboxed"
}

if [[ "$adhoc" == 1 ]]; then
  problem "the app is ad-hoc signed, a Developer ID signature is required"
else
  fw="$app/Contents/Frameworks/Sparkle.framework"
  check_code "$app" "NtfyMac.app"
  check_code "$app/Contents/MacOS/ntfy-mac" "bundled CLI"
  if [[ -d "$fw" ]]; then
    check_code "$fw" "Sparkle.framework"
    for item in "$fw"/Versions/B/XPCServices/*.xpc "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app"; do
      [[ -e "$item" ]] || continue
      check_code "$item" "Sparkle ${item##*/}"
    done
  fi
fi

if [[ "$mode" == --release ]]; then
  xcrun stapler validate "$app" >/dev/null || problem "no valid stapled notarization ticket"
  assessment="$(spctl --assess --type execute --verbose=4 "$app" 2>&1)" || problem "Gatekeeper rejects the app: $assessment"
  grep -q 'source=Notarized Developer ID' <<<"$assessment" || problem "Gatekeeper source is not Notarized Developer ID: $assessment"
fi

if [[ "$failed" != 0 ]]; then
  echo "verify-signature: FAILED for $app" >&2
  exit 1
fi
echo "verify-signature: ok ($([[ "$mode" == --release ]] && echo "Developer ID, notarized and stapled" || echo "Developer ID")) $app"
