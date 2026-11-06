#!/usr/bin/env bash
# Single entry point for code signing, notarization and stapling. Usage: scripts/sign.sh <path-to-app>
#
#   SIGN_IDENTITY=-             (default) ad-hoc, for `make check`, `make app`, `make snapshots` and CI
#   SIGN_IDENTITY=developer-id  the team's "Developer ID Application" certificate from the keychain search list,
#                               Hardened Runtime and a secure timestamp. Sparkle's helpers ship ad-hoc signed and
#                               notarization refuses them, so everything is re-signed inside out, never with --deep.
#   NOTARIZE=1                  (developer-id only) submit to Apple, wait, staple. NOTARY_TIMEOUT bounds the wait
#                               (default 40m). When it runs out or Apple answers Invalid, the script prints the
#                               submission id; RESUME_NOTARY_ID=<id> waits on that submission without re-signing or
#                               re-submitting (a changed byte would void it), then staples.
#
# The team id and the App Store Connect key come from APPLE_TEAM_ID, ASC_KEY_P8, ASC_KEY_ID, ASC_ISSUER_ID or, on the
# mini, secrets-run (scripts/apple-credentials.sh). The app needs no entitlements: it is not sandboxed.
# Every run ends in scripts/verify-signature.sh; a failed verification is a non-zero exit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:?usage: sign.sh <path-to-app>}"
identity="${SIGN_IDENTITY:--}"
notarize="${NOTARIZE:-0}"
resume_id="${RESUME_NOTARY_ID:-}"

fail() {
  echo "sign: $*" >&2
  exit 1
}

[[ -d "$app" ]] || fail "no app at $app"
[[ "$notarize" == 0 || "$notarize" == 1 ]] || fail "NOTARIZE must be 0 or 1"
[[ -z "$resume_id" || "$notarize" == 1 ]] || fail "RESUME_NOTARY_ID needs NOTARIZE=1"

if [[ "$identity" == "-" ]]; then
  [[ "$notarize" == 0 ]] || fail "NOTARIZE=1 needs SIGN_IDENTITY=developer-id (an ad-hoc app cannot be notarized)"
  codesign --force --deep --sign - "$app"
  "$root/scripts/verify-signature.sh" "$app"
  exit 0
fi
[[ "$identity" == "developer-id" ]] || fail "SIGN_IDENTITY must be '-' (ad-hoc) or 'developer-id', not '$identity'"

# shellcheck source=scripts/apple-credentials.sh
. "$root/scripts/apple-credentials.sh"
ASC_KEY_FILE=""
work="$(mktemp -d)"
trap 'rm -rf "$work"; [[ -z "$ASC_KEY_FILE" ]] || rm -f "$ASC_KEY_FILE"' EXIT

load_team || fail "no team id"
unlock_signing_keychain || fail "cannot unlock the signing keychain"
resolve_developer_id || fail "no signing identity"

sign_one() { # path, extra codesign options...
  local path="$1"
  shift
  codesign --force --options runtime --timestamp "$@" --sign "$IDENTITY" "$path"
}

# Inside out: XPC services, helper tools and apps, the framework, the bundled CLI, the app last (its seal covers all).
sign_bundle() {
  local fw="$app/Contents/Frameworks/Sparkle.framework" item
  if [[ -d "$fw" ]]; then
    for item in "$fw"/Versions/B/XPCServices/*.xpc; do
      [[ -e "$item" ]] || continue
      sign_one "$item" --preserve-metadata=entitlements
    done
    for item in "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw"; do
      [[ -e "$item" ]] || fail "Sparkle layout changed: no $item"
      sign_one "$item"
    done
  fi
  sign_one "$app/Contents/MacOS/ntfy-mac"
  sign_one "$app"
}

if [[ -z "$resume_id" ]]; then
  sign_bundle
  "$root/scripts/verify-signature.sh" "$app" --developer-id
fi
[[ "$notarize" == 1 ]] || exit 0

command -v jq >/dev/null || fail "jq is required for notarization"
load_notary_credentials || fail "no App Store Connect key"
notary=(xcrun notarytool)
auth=(--key "$ASC_KEY_FILE" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
timeout="${NOTARY_TIMEOUT:-40m}"

# A wait exits 0 on an Invalid verdict, so the status is read from the JSON.
if [[ -n "$resume_id" ]]; then
  result="$("${notary[@]}" wait "$resume_id" "${auth[@]}" --timeout "$timeout" --output-format json || true)"
else
  ditto -c -k --sequesterRsrc --keepParent "$app" "$work/notarize.zip"
  result="$("${notary[@]}" submit "$work/notarize.zip" "${auth[@]}" --wait --timeout "$timeout" --output-format json || true)"
fi
submission="${resume_id:-$(jq -r '.id // empty' <<<"$result" 2>/dev/null || true)}"
status="$(jq -r '.status // empty' <<<"$result" 2>/dev/null || true)"
echo "notarytool: id=${submission:-unknown} status=${status:-unknown}"
if [[ "$status" != "Accepted" ]]; then
  if [[ -n "$submission" ]]; then
    "${notary[@]}" log "$submission" "${auth[@]}" >&2 || true
    echo "to continue without re-signing: RESUME_NOTARY_ID=$submission SIGN_IDENTITY=developer-id NOTARIZE=1 scripts/sign.sh $app" >&2
  fi
  fail "notarization was not accepted (status: ${status:-none})"
fi

# The ticket can take a moment to reach the CDN after Accepted.
stapled=0
for attempt in 1 2 3 4 5; do
  if xcrun stapler staple "$app" >/dev/null 2>&1; then
    stapled=1
    break
  fi
  echo "stapler: ticket not available yet (attempt $attempt)" >&2
  sleep 10
done
[[ "$stapled" == 1 ]] || fail "could not staple the ticket"
"$root/scripts/verify-signature.sh" "$app" --release
