#!/usr/bin/env bash
# apple-slot.sh <cmd…> — run an Xcode build inside the mini's machine budget (same lock as iris's scripts/apple-slot).
#
#   on the mini  one Apple job at a time across repos (`lockf`), inside one of the factory's host-wide test slots
#   elsewhere    (hosted CI, the MacBook; no `factory`): the bare command
#
# Exit 75 = no slot or lock within the wait (APPLE_LOCK_WAIT seconds, default 1800).
set -u

[[ $# -gt 0 ]] || {
  echo "usage: apple-slot.sh <cmd…>" >&2
  exit 2
}

command -v factory >/dev/null 2>&1 || exec "$@"

exec lockf -t "${APPLE_LOCK_WAIT:-1800}" /tmp/iris-apple.lock factory slot run --name ntfy-mac-apple -- "$@"
