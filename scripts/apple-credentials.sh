# shellcheck shell=bash
# shellcheck disable=SC2034  # the variables are read by the scripts that source this file
# Sourced by sign.sh and verify-signature.sh: the Apple team id, the App Store Connect key for notarytool and the
# signing keychain. Callers `set -euo pipefail` first and own the temp-file cleanup (an EXIT trap on $ASC_KEY_FILE).
#
# Each value comes from its environment variable (CI) or, on the mini, from op://mini/apple-developer through
# `secrets-run` (never bare `op`: it hangs on a biometric prompt). No key material reaches argv or a log: notarytool
# takes the key as a file path.
#   APPLE_TEAM_ID  ASC_KEY_P8  ASC_KEY_ID  ASC_ISSUER_ID

APPLE_DEV_ITEM="op://mini/apple-developer"

# The key as notarytool needs it: real newlines, 64-character body lines, whatever shape the value arrives in
# (1Password turns the newlines of a concealed field into spaces; an env secret may hold a literal \n).
pem_normalize() {
  local value label body
  value="$(printf '%s' "$1" | sed 's/\\n/ /g' | tr -s '[:space:]' ' ')"
  label="$(printf '%s' "$value" | sed -nE 's/^ *-----BEGIN ([A-Z0-9 ]+)----- .*/\1/p')"
  if [[ -z "$label" ]]; then
    printf '%s\n' "$1"
    return
  fi
  body="$(printf '%s' "$value" | sed -E "s/^ *-----BEGIN $label----- *//; s/ *-----END $label----- *\$//" | tr -d '[:space:]')"
  printf -- '-----BEGIN %s-----\n%s\n-----END %s-----\n' "$label" "$(printf '%s' "$body" | fold -w 64)" "$label"
}

# apple_field <ENV_NAME> <1password-field>: prints the value, env first, secrets-run second.
apple_field() {
  local env_name="$1" field="$2" value="${!1:-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  if command -v secrets-run >/dev/null 2>&1; then
    secrets-run read "$APPLE_DEV_ITEM/$field" 2>/dev/null && return
  fi
  echo "missing $env_name: set it in the environment, or seed $APPLE_DEV_ITEM/$field for secrets-run" >&2
  return 1
}

# Sets TEAM.
load_team() {
  TEAM="$(apple_field APPLE_TEAM_ID team-id)" || return 1
}

# Sets ASC_KEY_FILE (a 0600 temp file holding the PEM), ASC_KEY_ID and ASC_ISSUER_ID.
load_notary_credentials() {
  local key
  key="$(apple_field ASC_KEY_P8 asc-key-p8)" || return 1
  ASC_KEY_ID="$(apple_field ASC_KEY_ID asc-key-id)" || return 1
  ASC_ISSUER_ID="$(apple_field ASC_ISSUER_ID asc-issuer-id)" || return 1
  ASC_KEY_FILE="$(mktemp "${TMPDIR:-/tmp}/ntfy-mac-asc-key.XXXXXX")"
  chmod 600 "$ASC_KEY_FILE"
  pem_normalize "$key" >"$ASC_KEY_FILE"
}

# The mini keeps the Developer ID identity in a dedicated keychain that a reboot leaves locked. Unlocks it when both the
# keychain and its password file exist; the password only passes through this call (`security` takes it as -p).
unlock_signing_keychain() {
  local keychain="${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/iris-signing.keychain-db}"
  local pass_file="${SIGNING_KEYCHAIN_PASS_FILE:-$HOME/.local/state/apple-developer/signing-keychain.pass}"
  [[ -r "$pass_file" && -e "$keychain" ]] || return 0
  security unlock-keychain -p "$(cat "$pass_file")" "$keychain" || {
    echo "could not unlock $keychain" >&2
    return 1
  }
}

# Sets IDENTITY to the SHA-1 of the team's "Developer ID Application" certificate (with its private key).
resolve_developer_id() {
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -v team="($TEAM)" '/Developer ID Application:/ && index($0, team) { print $2; exit }')"
  [[ -n "$IDENTITY" ]] || {
    echo "no 'Developer ID Application' certificate with a private key for the configured team in the keychain search list" >&2
    echo "(the Account Holder creates it; import the .p12, see docs/contributing.md)" >&2
    return 1
  }
}

TIME_SENSITIVE_KEY="com.apple.developer.usernotifications.time-sensitive"

# profile_ok <profile>: succeeds when the profile is a current Developer ID profile of the team for this app that
# carries the time-sensitive entitlement. Prints the reason on stderr otherwise. Needs $TEAM (load_team) and jq.
# (A profile holds dates and data, which plutil cannot convert whole to JSON: each part is extracted.)
profile_ok() {
  local profile="$1" plist ents expires all platform ok=0
  plist="$(mktemp)"
  if security cms -D -i "$profile" >"$plist" 2>/dev/null; then
    ents="$(plutil -extract Entitlements json -o - "$plist" 2>/dev/null)" || ents=""
    expires="$(plutil -extract ExpirationDate raw -o - "$plist" 2>/dev/null)" || expires=""
    all="$(plutil -extract ProvisionsAllDevices raw -o - "$plist" 2>/dev/null)" || all=""
    platform="$(plutil -extract Platform json -o - "$plist" 2>/dev/null)" || platform=""
    ok=1
  fi
  rm -f "$plist"
  [[ "$ok" == 1 && -n "$ents" ]] || {
    echo "the provisioning profile does not decode" >&2
    return 1
  }
  jq -e --arg key "$TIME_SENSITIVE_KEY" --arg team "$TEAM" --arg all "$all" --argjson platform "${platform:-[]}" \
    '.[$key] == true and .["com.apple.developer.team-identifier"] == $team
      and .["com.apple.application-identifier"] == ($team + ".com.jkrumm.ntfy-mac")
      and $all == "true" and ($platform | index("OSX") != null)' <<<"$ents" >/dev/null || {
    echo "the provisioning profile is not a Developer ID profile of this team for com.jkrumm.ntfy-mac with $TIME_SENSITIVE_KEY" >&2
    return 1
  }
  [[ "$(date -u +%Y-%m-%dT%H:%M:%SZ)" < "$expires" ]] || {
    echo "the provisioning profile expired on $expires" >&2
    return 1
  }
}

# Sets PROFILE_FILE to the Developer ID provisioning profile of the app: APPLE_DEVELOPER_ID_PROFILE_BASE64 (CI), else
# NTFY_MAC_PROFILE, else the file next to the other credentials on the mini. Empty when there is none; the caller
# decides whether that is fatal. $1 is a scratch directory for the decoded secret.
load_profile() {
  local work="$1" path="${NTFY_MAC_PROFILE:-$HOME/.local/state/apple-developer/ntfy-mac-developer-id.provisionprofile}"
  PROFILE_FILE=""
  if [[ -n "${APPLE_DEVELOPER_ID_PROFILE_BASE64:-}" ]]; then
    printf '%s' "$APPLE_DEVELOPER_ID_PROFILE_BASE64" | base64 --decode >"$work/embedded.provisionprofile"
    PROFILE_FILE="$work/embedded.provisionprofile"
  elif [[ -r "$path" ]]; then
    PROFILE_FILE="$path"
  fi
}
