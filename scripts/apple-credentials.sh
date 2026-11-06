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
