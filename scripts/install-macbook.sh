#!/usr/bin/env bash
# Installs the built NtfyMac.app on the MacBook by pulling, not pushing: the mini's `iumac` key runs a fixed verb
# list only (no rsync, no arbitrary commands), so the one MacBook-side command goes through ask-human.sh, which
# shows it in a native dialog on the MacBook and runs it on the owner's click. One dialog per install.
#
# Usage: scripts/install-macbook.sh <path to NtfyMac.app on this machine>
# The MacBook rsyncs the bundle from the mini (`ssh mini`), registers it, verifies the signature, prints identifier,
# authority and version, quits the running copy and opens the new one. The result is the .res file of the request.
set -euo pipefail

app="${1:?usage: install-macbook.sh <NtfyMac.app>}"
[[ -d "$app" ]] || { echo "no app bundle at $app (run make app)" >&2; exit 1; }
app="$(cd "$app" && pwd -P)"

ask_human="${ASK_HUMAN:-$HOME/SourceRoot/dotfiles/scripts/ask-human.sh}"
[[ -x "$ask_human" ]] || { echo "ask-human.sh not found at $ask_human" >&2; exit 1; }

mini_host="${MINI_HOST:-mini}"
# shellcheck disable=SC2088  # the tilde must reach the MacBook's shell unexpanded
dest='~/Applications/NtfyMac.app'
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

# Runs on the MacBook. Output stays short: the result keeps only the last 2000 characters.
# PROBE_CMD (optional) runs on the MacBook once before the copy and once after the relaunch, to compare state.
probe=""
[[ -n "${PROBE_CMD:-}" ]] && probe="echo '--- probe'; ${PROBE_CMD}; "
cmd="set -e; ${probe}mkdir -p ~/Applications; rsync -a --delete -e 'ssh -o BatchMode=yes' ${mini_host}:'${app}'/ ${dest}/"
cmd+="; ${lsregister} -f ${dest}; codesign --verify --deep --strict ${dest} && echo 'codesign: valid'"
cmd+="; codesign -dvv ${dest} 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)' | sed -E 's/^TeamIdentifier=.*/TeamIdentifier=<set>/; s/ \\\\([A-Z0-9]{10}\\\\)\$/ (<team>)/'"
cmd+="; echo \"version: \$(defaults read \$HOME/Applications/NtfyMac.app/Contents/Info CFBundleShortVersionString) build \$(defaults read \$HOME/Applications/NtfyMac.app/Contents/Info CFBundleVersion)\""
cmd+="; pkill -x NtfyMac || true; sleep 1; open ${dest} && echo 'relaunched: ${dest}'"
[[ -n "$probe" ]] && cmd+="; sleep 4; ${probe}"

set +e
id="$("$ask_human" ask "Install NtfyMac.app from ${mini_host} into ~/Applications and relaunch it" \
  --key ntfy-mac-install-macbook --cmd "$cmd" | head -n 1)"
rc=${PIPESTATUS[0]}
set -e

res="${XDG_STATE_HOME:-$HOME/.local/state}/human-queue/${id}.res"
if [[ -f "$res" ]]; then
  echo "MacBook result (request $id, exit $rc):"
  # output_tail is one JSON string; unescape the newlines for reading.
  sed -nE 's/.*"output_tail":"(.*)"\}?$/\1/p' "$res" | sed 's/\\n/\n/g; s/\\"/"/g'
else
  echo "no MacBook result for request $id (exit $rc): the dialog is still pending or the MacBook is unreachable" >&2
fi
exit "$rc"
