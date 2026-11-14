#!/usr/bin/env bash
# guest.sh <cell> — one cell of the clean-machine matrix, run INSIDE a macOS guest by matrix.sh.
#
# Prints evidence as it goes. Every judgement is one line:
#   CHECK ok|FAIL|NOTE <name> <detail>
# ok = the expectation held, FAIL = it did not (a defect or a broken cell), NOTE = evidence nobody judges here.
# A prompt is found without clicking it: a dialog is a window of some owner (windows.js) and the notification
# permission request is a usernoted log line. Nothing here can answer a prompt, so "permission kept" means the
# state is the same and no new request was made; it cannot mean "allowed".
#
# Files expected next to this script (matrix.sh copies them): install.sh, windows.js, fake-ntfy.py,
# ntfy-mac-<old>.rb and ntfy-mac-<new>.rb (the cask for each release).
# ok and note never fail, so `A && ok || bad` is a real if-else here.
# shellcheck disable=SC2015
set -uo pipefail

CELL="${1:?usage: guest.sh <cell>}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLD="${CM_OLD:-2.0.0}"
NEW="${CM_NEW:-2.0.1}"
BUNDLE="com.jkrumm.ntfy-mac"
DIRECT_APP="$HOME/Applications/NtfyMac.app"
CASK_APP="/Applications/NtfyMac.app"
PORT=18080
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

START="$(date '+%Y-%m-%d %H:%M:%S')"
FAILS=0

ok() { printf 'CHECK ok   %-34s %s\n' "$1" "${2:-}"; }
bad() {
  printf 'CHECK FAIL %-34s %s\n' "$1" "${2:-}"
  FAILS=$((FAILS + 1))
}
note() { printf 'CHECK NOTE %-34s %s\n' "$1" "${2:-}"; }
step() { printf '\n## %s\n' "$*"; }
# expect <name> <detail> <command...>: ok when the command succeeds.
expect() {
  local name="$1" detail="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then ok "$name" "$detail"; else bad "$name" "$detail"; fi
}

# ── Observation ───────────────────────────────────────────────────────────────

windows() { osascript -l JavaScript "$DIR/windows.js" 2>&1; }

# Notification permission requests for the app since $1 (a `log show` timestamp). The unified log lags a few seconds
# behind the event, so with $2 (the least count expected) it waits up to 20 s for the entry.
permission_requests() {
  local since="$1" want="${2:-0}" count tries=0
  while :; do
    count="$(log show --start "$since" --info --predicate 'process == "usernoted" AND eventMessage CONTAINS "Sending request for permission for com.jkrumm.ntfy-mac"' 2>/dev/null | grep -c "Sending request for permission")"
    [[ "${count:-0}" -ge "$want" || $tries -ge 10 ]] && break
    tries=$((tries + 1))
    sleep 2
  done
  echo "${count:-0}"
}

# Windows of owners nobody expects: ntfy-mac's own (onboarding, menu) are fine, everything else is a prompt.
unexpected_windows() { windows | sort -u | grep -Ev '^(ntfy-mac|NtfyMac)( \||$)' || true; }

check_no_prompt() {
  local label="$1" extra
  extra="$(unexpected_windows)"
  if [[ -z "$extra" ]]; then ok "no-dialog:$label" "no window besides ntfy-mac's own"; else bad "no-dialog:$label" "unexpected window(s): $(tr '\n' ';' <<<"$extra")"; fi
}

bundle_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null; }

describe_app() {
  local app="$1" sig
  sig="$(codesign -dvv "$app" 2>&1)"
  echo "app: $app version=$(bundle_version "$app")"
  echo "$sig" | grep -E '^(Identifier|Authority=Developer ID Application|Authority=Apple Root|Timestamp|flags)' | sed -E 's/(Authority=Developer ID Application:).*/\1 <name> (<team>)/' | sed 's/^/  /'
  echo "  quarantine: $(xattr -p com.apple.quarantine "$app" 2>/dev/null || echo none)"
  echo "  spctl: $(spctl --assess --type execute --verbose=4 "$app" 2>&1 | tr '\n' ' ')"
  echo "  embedded profile: $([[ -f "$app/Contents/embedded.provisionprofile" ]] && echo yes || echo no)"
}

running_apps() { pgrep -fl 'NtfyMac.app/Contents/MacOS/NtfyMac' | sed 's/^[0-9]* //' || true; }
app_pid() { pgrep -f 'NtfyMac.app/Contents/MacOS/NtfyMac$' | head -1; }

wait_for() { # wait_for <seconds> <command...>
  local limit="$1" n=0
  shift
  until "$@" >/dev/null 2>&1; do
    n=$((n + 1))
    [[ $n -gt $((limit * 2)) ]] && return 1
    sleep 0.5
  done
}

app_running() { [[ -n "$(app_pid)" ]]; }
app_gone() { [[ -z "$(app_pid)" ]]; }

stop_app() {
  pkill -x NtfyMac 2>/dev/null || true
  wait_for 20 app_gone
}

cli_of() { echo "$1/Contents/MacOS/ntfy-mac"; }

# The state a user would miss after an update.
data_state() {
  local label="$1" cli="$2" status
  status="$("$cli" status --json 2>/dev/null)"
  echo "data[$label]:"
  echo "  config sha: $(shasum -a 256 "$HOME/.config/ntfy-mac/config.json" 2>/dev/null | cut -c1-12)"
  echo "  team-pin sha: $(shasum -a 256 "$HOME/Library/Application Support/ntfy-mac/team-pin" 2>/dev/null | cut -c1-12)"
  echo "  keychain token item: $(security find-generic-password -s "$BUNDLE" >/dev/null 2>&1 && echo present || echo absent)"
  echo "  history total: $(jq -r '.history.total' <<<"$status" 2>/dev/null)"
  echo "  permission: $(jq -r 'if .permission.usable then "usable" else (.permission.problems[0].code // "unknown") end' <<<"$status" 2>/dev/null)"
  echo "  connection: $(jq -r '.connection' <<<"$status" 2>/dev/null)"
  echo "  app version: $(jq -r '.appVersion' <<<"$status" 2>/dev/null)"
}

# Prints one value of the state above (for comparisons).
state_value() { data_state "$1" "$2" | grep -E "^  $3" | head -1 | cut -d: -f2- | sed 's/^ //'; }

# ── Setup the app under test ──────────────────────────────────────────────────

start_fake_server() {
  curl -sf "http://127.0.0.1:$PORT/v1/account" >/dev/null 2>&1 && return 0
  nohup /usr/bin/python3 "$DIR/fake-ntfy.py" "$PORT" >/tmp/fake-ntfy.log 2>&1 </dev/null &
  disown
  wait_for 10 curl -sf "http://127.0.0.1:$PORT/v1/account"
}

# Gives the app a server (the fake one), a plaintext token (migrated into the Keychain on launch) and a history:
# `setup` refuses without notification permission, which a guest cannot grant, so the config is written as a 1.x
# install would have it.
seed() {
  local app="$1" cli total=0
  cli="$(cli_of "$app")"
  start_fake_server || { bad "fake-server" "did not start"; return 1; }
  mkdir -p "$HOME/.config/ntfy-mac"
  printf '{"url":"http://127.0.0.1:%s","token":"tk_cleanmachine00000000000000000000","allowInsecure":true,"extraTopics":["seed-topic"]}\n' "$PORT" >"$HOME/.config/ntfy-mac/config.json"
  stop_app
  open "$app"
  wait_for 30 app_running || { bad "seed-launch" "the app did not start"; return 1; }
  for _ in $(seq 1 40); do
    total="$("$cli" status --json 2>/dev/null | jq -r '.history.total // 0')"
    [[ "${total:-0}" -ge 3 ]] && break
    sleep 1
  done
  if [[ "${total:-0}" -ge 3 ]]; then ok "seeded" "history total $total, token moved to the Keychain"; else bad "seeded" "history total ${total:-0} after 40s"; fi
}

# ── Homebrew replica tap ──────────────────────────────────────────────────────

# The production tap still carries the formula (the cask goes live with the next Release run), so a local tap
# holds the cask `packaging/` renders, pointing at the real, published release zips.
REPLICA_TAP="local/cm"
replica_tap() { # replica_tap <version>
  local dir
  dir="$(brew --repository)/Library/Taps/local/homebrew-cm"
  mkdir -p "$dir/Casks"
  cp "$DIR/ntfy-mac-$1.rb" "$dir/Casks/ntfy-mac.rb"
  (
    cd "$dir" || exit 1
    [[ -d .git ]] || git init -q
    git add -A
    git -c user.name=cm -c user.email=cm@example.com commit -q -m "ntfy-mac $1" --allow-empty
  )
}

cask_install() {
  replica_tap "$1"
  brew install --cask "$REPLICA_TAP/ntfy-mac" 2>&1 | tail -25
  return "${PIPESTATUS[0]}"
}

# A cask install is quarantined, and macOS asks once before it opens such an app (cell cask-first-launch). Nothing in a
# guest can click that dialog, and the flag cannot be removed in place (App Management protects the bundle), so the
# cells that are about something else do what the click does: replace the bundle by a copy without the flag, before any
# launch.
approve_download() {
  local app="$1"
  note "quarantine-before-approval" "$(xattr -p com.apple.quarantine "$app" 2>/dev/null | sed -E 's/;[0-9A-Fa-f-]{36}$/;<id>/' || echo none)"
  pkill -9 -x NtfyMac 2>/dev/null || true
  mv "$app" "$app.q" && rsync -a "$app.q/" "$app/" && rm -rf "$app.q"
  [[ -z "$(xattr -p com.apple.quarantine "$app" 2>/dev/null)" ]] && codesign --verify --deep --strict "$app" 2>/dev/null && ok "download-approved" "copy without the quarantine flag, signature still valid" || bad "download-approved" "could not drop the flag"
}

common_install_checks() { # common_install_checks <app> <expected version>
  local app="$1" version="$2"
  [[ -d "$app" ]] && ok "installed" "$app" || bad "installed" "$app is missing"
  expect "codesign-valid" "codesign --verify --deep --strict" codesign --verify --deep --strict "$app"
  [[ "$(bundle_version "$app")" == "$version" ]] && ok "version" "$version" || bad "version" "expected $version, got $(bundle_version "$app")"
  spctl --assess --type execute --verbose=4 "$app" 2>&1 | grep -q 'Notarized Developer ID' && ok "gatekeeper" "accepted, source Notarized Developer ID" || bad "gatekeeper" "$(spctl --assess --type execute --verbose=4 "$app" 2>&1 | tr '\n' ' ')"
}

doctor_checks() { # doctor_checks <cli> <expect-channel>
  local json
  json="$("$1" doctor --json 2>/dev/null)"
  echo "doctor (selected checks):"
  jq -r '.checks[] | select(.name=="app" or .name=="permissions" or .name=="login-item" or .name=="duplicate-install" or .name=="update") | "  \(.name): \(.status) — \(.message)" + (if .detail then " [\(.detail)]" else "" end)' <<<"$json" 2>/dev/null ||
    echo "$json" | head -c 1500
  [[ "$(jq -r '.installChannel' <<<"$json" 2>/dev/null)" == "$2" ]] && ok "channel" "$2" || bad "channel" "expected $2, doctor says $(jq -r '.installChannel' <<<"$json" 2>/dev/null)"
}

# ── Cells ─────────────────────────────────────────────────────────────────────

cell_install_no_clt() {
  step "install.sh on a Mac with no Command Line Tools (the pristine image)"
  note "developer-tools" "xcode-select -p: $(xcode-select -p 2>&1 | head -1)"
  local out rc
  out="$(NTFY_MAC_NO_LAUNCH=1 bash "$DIR/install.sh" 2>&1)"
  rc=$?
  echo "$out" | tail -5
  sleep 3
  note "install.sh exit" "$rc"
  if [[ $rc -eq 0 && -d "$DIRECT_APP" ]]; then ok "install-on-clean-mac" "installed with no developer tools"; else bad "install-on-clean-mac" "install.sh exit $rc, no app: $(tail -1 <<<"$out")"; fi
  local owners
  owners="$(unexpected_windows)"
  if [[ -z "$owners" ]]; then ok "no-dialog:install" "none"; else bad "no-dialog:install" "dialog on screen: $(tr '\n' ';' <<<"$owners")"; fi
}

cell_direct_fresh() {
  step "install.sh, latest release, clean Mac"
  [[ -z "$(running_apps)" && ! -d "$DIRECT_APP" && ! -d "$CASK_APP" ]] && ok "clean-start" "no copy, nothing running" || bad "clean-start" "not clean"
  local rc
  bash "$DIR/install.sh" 2>&1 | tail -6
  rc="${PIPESTATUS[0]}"
  [[ $rc -eq 0 ]] && ok "install.sh" "exit 0" || { bad "install.sh" "exit $rc"; return; }
  describe_app "$DIRECT_APP"
  common_install_checks "$DIRECT_APP" "$NEW"
  [[ "$(xattr -p com.apple.quarantine "$DIRECT_APP" 2>/dev/null)" == "" ]] && ok "no-quarantine" "curl install carries no quarantine flag" || bad "no-quarantine" "quarantine flag set"
  wait_for 30 app_running && ok "app-opens" "$(running_apps | head -1)" || bad "app-opens" "not running after install.sh"
  sleep 6
  check_no_prompt "first-launch"
  local requests
  requests="$(permission_requests "$START" 1)"
  [[ "$requests" == "1" ]] && ok "one-permission-request" "exactly one at first launch" || bad "one-permission-request" "$requests request(s) at first launch"
  doctor_checks "$(cli_of "$DIRECT_APP")" direct
  seed "$DIRECT_APP"
  data_state "after seed" "$(cli_of "$DIRECT_APP")"
  step "second run of install.sh (the documented way to update)"
  local before after
  before="$(state_value x "$(cli_of "$DIRECT_APP")" 'config sha')|$(state_value x "$(cli_of "$DIRECT_APP")" 'history total')"
  bash "$DIR/install.sh" 2>&1 | tail -3
  wait_for 30 app_running || bad "relaunch" "app not running after the second install.sh"
  sleep 8
  after="$(state_value x "$(cli_of "$DIRECT_APP")" 'config sha')|$(state_value x "$(cli_of "$DIRECT_APP")" 'history total')"
  [[ "$before" == "$after" ]] && ok "rerun-keeps-data" "$after" || bad "rerun-keeps-data" "before $before after $after"
  check_no_prompt "rerun"
}

cell_direct_upgrade() {
  step "install $OLD (the real published release)"
  NTFY_MAC_VERSION="$OLD" bash "$DIR/install.sh" 2>&1 | tail -4
  wait_for 30 app_running || { bad "app-opens" "$OLD did not start"; return; }
  common_install_checks "$DIRECT_APP" "$OLD"
  seed "$DIRECT_APP"
  local cli t0
  cli="$(cli_of "$DIRECT_APP")"
  data_state "before upgrade" "$cli"
  local b_cfg b_hist b_pin b_perm
  b_cfg="$(state_value x "$cli" 'config sha')"
  b_hist="$(state_value x "$cli" 'history total')"
  b_pin="$(state_value x "$cli" 'team-pin sha')"
  b_perm="$(state_value x "$cli" 'permission')"
  t0="$(date '+%Y-%m-%d %H:%M:%S')"
  step "upgrade to $NEW with install.sh (rerun to update)"
  NTFY_MAC_VERSION="$NEW" bash "$DIR/install.sh" 2>&1 | tail -4
  wait_for 30 app_running || bad "relaunch" "app not running after the upgrade"
  sleep 8
  cli="$(cli_of "$DIRECT_APP")"
  describe_app "$DIRECT_APP"
  common_install_checks "$DIRECT_APP" "$NEW"
  data_state "after upgrade" "$cli"
  [[ "$(state_value x "$cli" 'config sha')" == "$b_cfg" ]] && ok "config-kept" "$b_cfg" || bad "config-kept" "$b_cfg → $(state_value x "$cli" 'config sha')"
  [[ "$(state_value x "$cli" 'history total')" -ge "$b_hist" ]] && ok "history-kept" "$b_hist → $(state_value x "$cli" 'history total')" || bad "history-kept" "$b_hist → $(state_value x "$cli" 'history total')"
  [[ "$(state_value x "$cli" 'team-pin sha')" == "$b_pin" ]] && ok "team-pin-kept" "unchanged" || bad "team-pin-kept" "changed"
  [[ "$(state_value x "$cli" 'keychain token item')" == "present" ]] && ok "token-kept" "Keychain item present" || bad "token-kept" "Keychain item gone"
  [[ "$(state_value x "$cli" 'permission')" == "$b_perm" ]] && ok "permission-state-kept" "$b_perm (a guest cannot grant it; see the owner checklist)" || bad "permission-state-kept" "$b_perm → $(state_value x "$cli" 'permission')"
  [[ "$(permission_requests "$t0")" == "0" ]] && ok "no-new-permission-request" "0 since the upgrade" || bad "no-new-permission-request" "$(permission_requests "$t0") request(s) since the upgrade"
  check_no_prompt "upgrade"
  doctor_checks "$cli" direct
}

cell_direct_sparkle() {
  step "install $OLD, then ask the app to update through Sparkle"
  NTFY_MAC_VERSION="$OLD" bash "$DIR/install.sh" 2>&1 | tail -3
  wait_for 30 app_running || { bad "app-opens" "$OLD did not start"; return; }
  seed "$DIRECT_APP"
  local cli
  cli="$(cli_of "$DIRECT_APP")"
  sleep 5
  echo "update --check: $("$cli" update --check 2>&1 | head -3 | tr '\n' ' ')"
  "$cli" update --check 2>&1 | grep -q "Update available: $NEW" && ok "update-check" "reports $NEW with no window" || bad "update-check" "did not report $NEW"
  check_no_prompt "update-check"
  local before after
  before="$(windows | grep -c "^ntfy-mac")"
  echo "update: $("$cli" update 2>&1 | head -3 | tr '\n' ' ')"
  sleep 8
  after="$(windows | grep -c "^ntfy-mac")"
  note "sparkle-window" "ntfy-mac windows before $before, after $after (a window title needs Screen Recording permission, so the window is counted)"
  if [[ "$after" -gt "$before" ]]; then ok "sparkle-prompt" "a new window appeared (Sparkle's prompt, waiting for a click, as designed)"; else note "sparkle-prompt" "no new window counted; the prompt itself is not provable here"; fi
  note "owner-checklist" "the approval click and the relaunch were proven on the MacBook (Issue 1045); not repeatable without a click"
}

cell_cask_first_launch() {
  step "brew install --cask, then open the app the way a user does"
  cask_install "$NEW" && ok "brew-install" "exit 0" || { bad "brew-install" "failed"; return; }
  note "quarantine" "$(xattr -p com.apple.quarantine "$CASK_APP" 2>/dev/null | sed -E 's/;[0-9A-Fa-f-]{36}$/;<id>/' || echo none)"
  open "$CASK_APP" 2>&1 || true
  sleep 10
  local owners
  owners="$(unexpected_windows)"
  note "windows" "$(tr '\n' ';' <<<"$owners")"
  if grep -q CoreServicesUIAgent <<<"$owners"; then
    note "gatekeeper-first-launch" "yes: macOS asks once before it opens an app Homebrew downloaded (the standard check of any quarantined download; the curl install carries no flag and shows none). A user clicks Open; a guest cannot."
  else
    ok "gatekeeper-first-launch" "no dialog"
  fi
  note "permission-requests" "$(permission_requests "$START") notification permission request(s) while the dialog is open (the app waits behind it)"
}

cell_cask_fresh() {
  step "brew install --cask from the replica tap ($NEW)"
  [[ -z "$(running_apps)" && ! -d "$DIRECT_APP" && ! -d "$CASK_APP" ]] && ok "clean-start" "no copy" || bad "clean-start" "not clean"
  cask_install "$NEW" && ok "brew-install" "exit 0" || { bad "brew-install" "failed"; return; }
  describe_app "$CASK_APP"
  common_install_checks "$CASK_APP" "$NEW"
  [[ -x /opt/homebrew/bin/ntfy-mac ]] && ok "cli-link" "$(readlink /opt/homebrew/bin/ntfy-mac)" || bad "cli-link" "/opt/homebrew/bin/ntfy-mac missing"
  approve_download "$CASK_APP"
  open "$CASK_APP"
  wait_for 30 app_running && ok "app-opens" "$(running_apps | head -1)" || bad "app-opens" "not running"
  sleep 6
  check_no_prompt "first-launch"
  local requests
  requests="$(permission_requests "$START" 1)"
  [[ "$requests" == "1" ]] && ok "one-permission-request" "exactly one at first launch" || bad "one-permission-request" "$requests request(s) at first launch"
  doctor_checks "$(cli_of "$CASK_APP")" direct
  seed "$CASK_APP"
  data_state "after seed" "$(cli_of "$CASK_APP")"
}

cell_cask_upgrade() {
  step "brew install --cask $OLD, seed"
  cask_install "$OLD" && ok "brew-install" "$OLD" || { bad "brew-install" "failed"; return; }
  approve_download "$CASK_APP"
  seed "$CASK_APP"
  local cli
  cli="$(cli_of "$CASK_APP")"
  data_state "before upgrade" "$cli"
  local b_cfg b_hist b_pin b_perm t0
  b_cfg="$(state_value x "$cli" 'config sha')"
  b_hist="$(state_value x "$cli" 'history total')"
  b_pin="$(state_value x "$cli" 'team-pin sha')"
  b_perm="$(state_value x "$cli" 'permission')"
  t0="$(date '+%Y-%m-%d %H:%M:%S')"
  step "the tap moves to $NEW: plain brew upgrade (auto_updates: expect it to skip), then --greedy"
  replica_tap "$NEW"
  brew update-reset >/dev/null 2>&1 || true
  echo "brew outdated: [$(brew outdated --cask 2>&1 | tr '\n' ' ')]"
  echo "brew upgrade --cask (no name, what a user runs): $(brew upgrade --cask 2>&1 | grep -E "^(==>|Warning|Error|🍺)" | tr '\n' ';')"
  if [[ "$(bundle_version "$CASK_APP")" == "$OLD" ]]; then
    note "brew-upgrade" "a bare brew upgrade left $OLD (auto_updates: Sparkle owns the update); trying --greedy"
    echo "brew upgrade --cask --greedy: $(brew upgrade --cask --greedy 2>&1 | grep -E "^(==>|Warning|Error|🍺)" | tr '\n' ';')"
  else
    note "brew-upgrade" "a bare brew upgrade moved the cask copy to $(bundle_version "$CASK_APP") although the cask has auto_updates"
  fi
  [[ "$(bundle_version "$CASK_APP")" == "$NEW" ]] && ok "brew-upgrade-reached-new" "$OLD → $NEW" || { bad "brew-upgrade-reached-new" "version is $(bundle_version "$CASK_APP")"; return; }
  describe_app "$CASK_APP"
  note "app-after-brew-upgrade" "running: $(running_apps | head -1)"
  approve_download "$CASK_APP"
  open "$CASK_APP"
  wait_for 30 app_running || bad "relaunch" "app does not start after the upgrade"
  sleep 8
  cli="$(cli_of "$CASK_APP")"
  data_state "after upgrade" "$cli"
  [[ "$(state_value x "$cli" 'config sha')" == "$b_cfg" ]] && ok "config-kept" "$b_cfg" || bad "config-kept" "$b_cfg → $(state_value x "$cli" 'config sha')"
  [[ "$(state_value x "$cli" 'history total')" -ge "$b_hist" ]] && ok "history-kept" "$b_hist → $(state_value x "$cli" 'history total')" || bad "history-kept" "$b_hist → $(state_value x "$cli" 'history total')"
  [[ "$(state_value x "$cli" 'team-pin sha')" == "$b_pin" ]] && ok "team-pin-kept" "unchanged" || bad "team-pin-kept" "changed"
  [[ "$(state_value x "$cli" 'keychain token item')" == "present" ]] && ok "token-kept" "Keychain item present" || bad "token-kept" "Keychain item gone"
  [[ "$(state_value x "$cli" 'permission')" == "$b_perm" ]] && ok "permission-state-kept" "$b_perm (a guest cannot grant it; see the owner checklist)" || bad "permission-state-kept" "$b_perm → $(state_value x "$cli" 'permission')"
  [[ "$(permission_requests "$t0")" == "0" ]] && ok "no-new-permission-request" "0 since the upgrade" || bad "no-new-permission-request" "$(permission_requests "$t0") request(s) since the upgrade"
  check_no_prompt "upgrade"
}

cell_together_direct_then_cask() {
  step "direct install $NEW first, then brew install --cask"
  bash "$DIR/install.sh" 2>&1 | tail -2
  wait_for 30 app_running || { bad "app-opens" "direct copy did not start"; return; }
  seed "$DIRECT_APP"
  local b_hist
  b_hist="$(state_value x "$(cli_of "$DIRECT_APP")" 'history total')"
  data_state "direct only" "$(cli_of "$DIRECT_APP")"
  cask_install "$NEW"
  echo "brew install --cask exit: ${PIPESTATUS[0]}"
  echo "copies: $(find "$HOME/Applications" /Applications -maxdepth 1 -name NtfyMac.app 2>/dev/null | tr '\n' ' ')"
  [[ -d "$DIRECT_APP" && -d "$CASK_APP" ]] && note "two-copies" "both copies exist (brew did not refuse)" || note "two-copies" "only one copy exists"
  note "running-after-cask-install" "$(running_apps | tr '\n' ';')"
  approve_download "$CASK_APP"
  step "which copy answers, and what the user is told"
  local json
  for app in "$DIRECT_APP" "$CASK_APP"; do
    [[ -d "$app" ]] || continue
    json="$("$(cli_of "$app")" doctor --json 2>&1)"
    echo "doctor from $app: $(jq -r '.checks[] | select(.name=="duplicate-install") | "\(.status): \(.message) \(.detail // "")"' <<<"$json" 2>&1 | tr '\n' ';')"
    jq -e '.checks[] | select(.name=="duplicate-install" and .status=="warn")' <<<"$json" >/dev/null && ok "duplicate-warning:$(basename "$(dirname "$app")")" "doctor names both copies" || bad "duplicate-warning:$(basename "$(dirname "$app")")" "no duplicate warning; doctor said: $(head -c 300 <<<"$json" | tr '\n' ' ')"
  done
  stop_app
  open -b "$BUNDLE"
  wait_for 30 app_running
  note "open -b picks" "$(running_apps | head -1)"
  stop_app
  "$(cli_of "$CASK_APP")" start 2>&1 | head -2
  wait_for 30 app_running
  note "ntfy-mac start (cask CLI) opens" "$(running_apps | head -1)"
  sleep 5
  local started
  started="$(running_apps | head -1)"
  [[ "$(running_apps | wc -l | tr -d ' ')" == "1" ]] && ok "one-process" "never two copies running: $started" || bad "one-process" "$(running_apps | tr '\n' ';')"
  [[ "$(state_value x "$(cli_of "$CASK_APP")" 'history total')" -ge "$b_hist" ]] && ok "history-kept" "$b_hist rows still there" || bad "history-kept" "history lost"
  check_no_prompt "together"
  step "hand-off: start the other copy while the first one runs"
  local first second
  first="$(running_apps | head -1)"
  open "$DIRECT_APP"
  sleep 8
  second="$(running_apps | tr '\n' ';')"
  note "open other copy by path" "was: $first; now: $second"
  "$(cli_of "$DIRECT_APP")" start 2>&1 | head -2
  sleep 8
  second="$(running_apps | tr '\n' ';')"
  note "ntfy-mac start (direct CLI)" "now: $second"
  if [[ "$(running_apps | wc -l | tr -d ' ')" == "1" ]]; then
    ok "hand-off" "a second launch left one process running: $(running_apps | head -1)"
  else
    bad "hand-off" "two copies run at once: $second (no hand-off: the shared app group and its owner lock are not built yet)"
  fi
  [[ "$(state_value x "$(cli_of "$CASK_APP")" 'history total')" -ge "$b_hist" ]] && ok "history-kept-after-second-launch" "$b_hist rows" || bad "history-kept-after-second-launch" "history changed"
  check_no_prompt "hand-off"
}

cell_together_cask_then_direct() {
  step "brew cask first, then install.sh"
  cask_install "$NEW" && ok "brew-install" "$NEW" || { bad "brew-install" "failed"; return; }
  approve_download "$CASK_APP"
  seed "$CASK_APP"
  local b_hist out rc
  b_hist="$(state_value x "$(cli_of "$CASK_APP")" 'history total')"
  out="$(bash "$DIR/install.sh" 2>&1)"
  rc=$?
  echo "$out" | tail -3
  [[ $rc -eq 1 ]] && ok "install.sh-refuses" "exit 1: $(tail -1 <<<"$out" | cut -c1-120)" || bad "install.sh-refuses" "exit $rc"
  [[ ! -d "$DIRECT_APP" ]] && ok "no-second-copy" "nothing installed into ~/Applications" || bad "no-second-copy" "$DIRECT_APP exists"
  app_running && ok "cask-copy-untouched" "still running: $(running_apps | head -1)" || bad "cask-copy-untouched" "the cask copy is not running"
  [[ "$(state_value x "$(cli_of "$CASK_APP")" 'history total')" -ge "$b_hist" ]] && ok "history-kept" "$b_hist" || bad "history-kept" "history lost"
  grep -q 'brew uninstall --cask ntfy-mac' <<<"$out" && ok "remedy-named" "message names the cask uninstall" || bad "remedy-named" "message does not name the remedy"
  check_no_prompt "refusal"
}

# ── Run ───────────────────────────────────────────────────────────────────────

echo "cell: $CELL   $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))   old=$OLD new=$NEW   start=$START"
case "$CELL" in
  install-no-clt) cell_install_no_clt ;;
  direct-fresh) cell_direct_fresh ;;
  direct-upgrade) cell_direct_upgrade ;;
  direct-sparkle) cell_direct_sparkle ;;
  cask-first-launch) cell_cask_first_launch ;;
  cask-fresh) cell_cask_fresh ;;
  cask-upgrade) cell_cask_upgrade ;;
  together-direct-then-cask) cell_together_direct_then_cask ;;
  together-cask-then-direct) cell_together_cask_then_direct ;;
  *)
    echo "unknown cell: $CELL" >&2
    exit 2
    ;;
esac
echo
echo "RESULT $CELL fails=$FAILS"
[[ $FAILS -eq 0 ]]
