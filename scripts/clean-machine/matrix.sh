#!/usr/bin/env bash
# matrix.sh — the clean-machine matrix, host side (the mini). See docs/clean-machine.md.
#
#   matrix.sh run <15|26|all> [cell...]     per macOS, one at a time: build its bases, run the cells, delete the VMs.
#                                           Each cell runs in a fresh APFS clone of its base, deleted when the cell ends.
#                                           CM_KEEP_BASES=1 keeps the bases for the next run.
#   matrix.sh bases <15|26|all>             only build the bases (macOS from Apple's IPSW through Lima):
#                                           cm-<os>      pristine: first boot done, auto-login to the GUI session
#                                           cm-<os>-clt  + Command Line Tools (what install.sh and Homebrew need)
#                                           cm-<os>-brew + Homebrew
#   matrix.sh cells                         list the cells and the base each one needs
#   matrix.sh status                        list the VMs
#   matrix.sh clean <15|26|all>             delete every VM of that macOS and the IPSW cache
#
# Results: $CM_OUT (default .build/clean-machine/<timestamp>): <os>-<cell>.log per cell and summary.txt.
# Each VM unit (a base, a cell) runs inside the shared Apple slot (apple-slot.sh), so it does not compete with builds.
# Disk: the mini panicked at 94% full (2026-11-13). The driver refuses to start a VM below CM_MIN_FREE_GIB (40) free on
# the Data volume, keeps one macOS at a time and deletes the IPSW cache once a base exists.
# Env: CM_OLD / CM_NEW = the two published releases to install and upgrade between (default 2.0.0 and 2.0.1).
# The guest commands are single-quoted on purpose: they expand inside the guest.
# shellcheck disable=SC2016
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/scripts/clean-machine"
OLD="${CM_OLD:-2.0.0}"
NEW="${CM_NEW:-2.0.1}"
OUT="${CM_OUT:-$ROOT/.build/clean-machine/$(date +%Y%m%d-%H%M%S)}"
GUEST_DIR="/tmp/cm"

# cell -> base suffix ("" = pristine)
base_of() {
  case "$1" in
    install-no-clt) echo "" ;;
    direct-fresh | direct-upgrade | direct-sparkle) echo "-clt" ;;
    cask-first-launch | cask-fresh | cask-upgrade | cask-sparkle-then-brew | together-direct-then-cask | together-cask-then-direct) echo "-brew" ;;
    *) return 1 ;;
  esac
}
CELLS=(install-no-clt direct-fresh direct-upgrade direct-sparkle cask-first-launch cask-fresh cask-upgrade cask-sparkle-then-brew together-direct-then-cask together-cask-then-direct)

# The mini panicked at 94% disk (2026-11-13): one macOS at a time, every clone deleted when its cell ends, and no
# new VM below CM_MIN_FREE_GIB free on the Data volume.
MIN_FREE_GIB="${CM_MIN_FREE_GIB:-40}"
disk_guard() {
  local free
  free="$(df -k /System/Volumes/Data | awk 'NR == 2 {print int($4 / 1048576)}')"
  [[ "$free" -ge "$MIN_FREE_GIB" ]] || die "only $free GiB free on the Data volume (minimum $MIN_FREE_GIB); stopping before the next VM. Free space, or run matrix.sh clean all"
}

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() {
  echo "matrix.sh: $*" >&2
  exit 1
}

# A unit that boots a VM (a base, one cell) runs in the Apple slot, so builds of other repos wait at most one unit:
# the driver calls itself with an internal verb under apple-slot.sh. The VM is gone again when the unit ends.
export CM_OUT="$OUT" CM_OLD="$OLD" CM_NEW="$NEW"
slot() { "$ROOT/scripts/apple-slot.sh" "${BASH_SOURCE[0]}" "$@"; }
# A failed or killed run must not leave its clone running (and growing) behind it.
# Cleanup on exit. A base whose build did not finish is deleted (PARTIAL_BASE), so the next run rebuilds it instead of
# cloning a half-built one. The run clones are deleted only by `run` itself (CLEAN_RUNS): `status` or `cells` in another
# shell must never remove the VM of a cell that is running.
PARTIAL_BASE=""
CLEAN_RUNS=""
cleanup_runs() {
  local vm
  for vm in $(limactl list --format "{{.Name}}" 2>/dev/null | grep "^cmrun-"); do limactl delete -f "$vm" >/dev/null 2>&1; done
}
on_exit() {
  [[ -z "$PARTIAL_BASE" ]] || limactl delete -f "$PARTIAL_BASE" >/dev/null 2>&1
  [[ -z "$CLEAN_RUNS" ]] || cleanup_runs
}
trap on_exit EXIT

oses() {
  case "$1" in
    15 | 26) echo "$1" ;;
    all) echo "15 26" ;;
    *) die "macOS must be 15, 26 or all" ;;
  esac
}

exists() { # captured first: with pipefail, grep -q closing the pipe would fail limactl with SIGPIPE
  local names
  names="$(limactl list --format '{{.Name}}' 2>/dev/null)"
  grep -qx "$1" <<<"$names"
}
running() { [[ "$(limactl list --format '{{.Name}} {{.Status}}' 2>/dev/null | awk -v n="$1" '$1 == n {print $2}')" == "Running" ]]; }
# Guest commands that need root use sudo -A: the password file of the guest user answers it.
GUEST_SUDO='export SUDO_ASKPASS=/tmp/cm-askpass; printf "#!/bin/sh\ncat ~/password\n" >$SUDO_ASKPASS; chmod +x $SUDO_ASKPASS;'
gsh() {
  local vm="$1"
  shift
  limactl shell "$vm" -- bash -c "$*"
}

wait_gui() { # the GUI session is up when the console user is the guest user, not root
  local vm="$1" user
  for _ in $(seq 1 90); do
    user="$(limactl shell "$vm" -- stat -f%Su /dev/console 2>/dev/null || true)"
    [[ -n "$user" && "$user" != root ]] && return 0
    sleep 4
  done
  die "$vm: no GUI session after 6 minutes"
}

start_vm() { # start_vm <vm> [nogui]: nogui waits for ssh only (before auto-login exists there is no GUI session)
  running "$1" || limactl start "$1" --tty=false >/dev/null 2>&1 || die "cannot start $1"
  [[ "${2:-}" == nogui ]] || wait_gui "$1"
}

stop_vm() { running "$1" && limactl stop "$1" >/dev/null 2>&1; }

# Auto-login: a GUI session is what makes notifications, Gatekeeper and login items behave like a user's Mac.
# `sysadminctl -autologin` fails headless (SACSetAutoLoginPassword error 22), so /etc/kcpassword is written by hand:
# the password XORed with the fixed key, padded to a multiple of 12.
enable_autologin() {
  local vm="$1"
  gsh "$vm" '[[ -f /etc/kcpassword ]]' 2>/dev/null && return 0
  log "$vm: enabling auto-login"
  gsh "$vm" "$GUEST_SUDO"'
    pw=$(cat ~/password)
    sudo -A defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser "$USER"
    PW="$pw" perl -e '"'"'my @k=(0x7D,0x89,0x52,0x23,0xD2,0xBC,0xDD,0xEA,0xA3,0xB9,0x1F); my @b=map ord,split //,$ENV{PW}; push @b,0; push @b,0 while @b%12; my $o=""; $o.=chr($b[$_]^$k[$_%11]) for 0..$#b; open F,">/tmp/kcp" or die; binmode F; print F $o; close F'"'"'
    sudo -A install -m 600 -o root -g wheel /tmp/kcp /etc/kcpassword; rm /tmp/kcp
    sudo -A shutdown -r now' >/dev/null 2>&1 || true
  sleep 20
  wait_gui "$vm"
}

build_pristine() {
  local os="$1" vm="cm-$1"
  disk_guard
  if ! exists "$vm"; then
    log "$vm: creating (downloads the IPSW, installs macOS; about 10 minutes)"
    PARTIAL_BASE="$vm"
    limactl start --name="$vm" --tty=false "$HERE/macos-$os.yaml" >"$OUT/create-$os.log" 2>&1 || die "creating $vm failed, see $OUT/create-$os.log"
    # The IPSW (about 17 GB) is only needed to create the VM.
    rm -rf "$HOME/Library/Caches/lima/download"
  fi
  start_vm "$vm" nogui
  enable_autologin "$vm"
  stop_vm "$vm"
  PARTIAL_BASE=""
}

build_clt() {
  local os="$1" vm="cm-$1-clt" label
  exists "$vm" && return 0
  disk_guard
  limactl clone "cm-$os" "$vm" --tty=false >/dev/null 2>&1 || die "cannot clone cm-$os"
  PARTIAL_BASE="$vm"
  start_vm "$vm"
  log "$vm: installing the Command Line Tools"
  label="$(gsh "$vm" "$GUEST_SUDO"'
    sudo -A touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    sudo -A softwareupdate -l 2>&1 | sed -n "s/^\* Label: //p" | grep "Command Line Tools" | sort -V | tail -1')"
  [[ -n "$label" ]] || die "$vm: no Command Line Tools label offered"
  gsh "$vm" "$GUEST_SUDO sudo -A softwareupdate -i \"$label\" >/tmp/clt.log 2>&1; xcode-select -p" | grep -q CommandLineTools || die "$vm: Command Line Tools install failed"
  stop_vm "$vm"
  PARTIAL_BASE=""
}

build_brew() {
  local os="$1" vm="cm-$1-brew"
  exists "$vm" && return 0
  disk_guard
  limactl clone "cm-$os-clt" "$vm" --tty=false >/dev/null 2>&1 || die "cannot clone cm-$os-clt"
  PARTIAL_BASE="$vm"
  start_vm "$vm"
  log "$vm: installing Homebrew"
  # The installer needs passwordless sudo for its own run; the drop-in is removed again.
  gsh "$vm" "$GUEST_SUDO"'
    echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo -A tee /etc/sudoers.d/cm-brew >/dev/null
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >/tmp/brew-install.log 2>&1; rc=$?
    sudo -A rm -f /etc/sudoers.d/cm-brew; exit $rc' || die "$vm: Homebrew install failed"
  gsh "$vm" '/opt/homebrew/bin/brew --version' | head -1 >&2
  stop_vm "$vm"
  PARTIAL_BASE=""
}

cmd_bases() {
  mkdir -p "$OUT"
  local os
  for os in $(oses "${1:-}"); do
    slot _pristine "$os" || die "base cm-$os failed"
    slot _clt "$os" || die "base cm-$os-clt failed"
    slot _brew "$os" || die "base cm-$os-brew failed"
  done
}

# The cask the tap job would render for a published release, from that release's own SHA256SUMS.
render_cask() {
  local version="$1" sha
  sha="$(curl -fsSL "https://github.com/jkrumm/ntfy-mac/releases/download/v$version/SHA256SUMS" | awk -v f="NtfyMac-$version.zip" '$2 == f {print $1}')"
  [[ -n "$sha" ]] || die "no checksum for NtfyMac-$version.zip in the v$version release"
  "$ROOT/scripts/render-cask.sh" "$version" "$sha"
}

run_cell() {
  local os="$1" cell="$2" base run log rc
  base="cm-$os$(base_of "$cell")"
  run="cmrun-$os-$cell"
  log="$OUT/$os-$cell.log"
  exists "$base" || die "$base does not exist: run 'matrix.sh bases $os'"
  exists "$run" && limactl delete -f "$run" >/dev/null 2>&1
  disk_guard
  log "$os $cell: clone of $base"
  limactl clone "$base" "$run" --tty=false >/dev/null 2>&1 || die "cannot clone $base"
  start_vm "$run"
  gsh "$run" "rm -rf $GUEST_DIR && mkdir -p $GUEST_DIR"
  for f in "$ROOT/install.sh" "$HERE/guest.sh" "$HERE/windows.js" "$HERE/fake-ntfy.py" "$OUT/ntfy-mac-$OLD.rb" "$OUT/ntfy-mac-$NEW.rb"; do
    limactl copy "$f" "$run:$GUEST_DIR/$(basename "$f")" >/dev/null 2>&1 || die "cannot copy $f"
  done
  log "$os $cell: running"
  limactl shell "$run" -- env CM_OLD="$OLD" CM_NEW="$NEW" bash "$GUEST_DIR/guest.sh" "$cell" >"$log" 2>&1
  rc=$?
  log "$os $cell: exit $rc"
  stop_vm "$run"
  limactl delete -f "$run" >/dev/null 2>&1
  return $rc
}

cmd_run() {
  mkdir -p "$OUT"
  CLEAN_RUNS=1
  local target="${1:-}" os cell failed=0
  shift || true
  local cells=("$@")
  [[ ${#cells[@]} -gt 0 ]] || cells=("${CELLS[@]}")
  render_cask "$OLD" >"$OUT/ntfy-mac-$OLD.rb"
  render_cask "$NEW" >"$OUT/ntfy-mac-$NEW.rb"
  for os in $(oses "$target"); do
    # One macOS at a time: its bases are built, used and deleted before the next macOS starts.
    cmd_bases "$os"
    for cell in "${cells[@]}"; do
      base_of "$cell" >/dev/null || die "unknown cell: $cell (matrix.sh cells)"
      slot _cell "$os" "$cell" || failed=$((failed + 1))
    done
    [[ -n "${CM_KEEP_BASES:-}" ]] || cmd_clean "$os"
  done
  {
    echo "clean-machine matrix $(date -u +%FT%TZ)  old=$OLD new=$NEW"
    for os in $(oses "$target"); do
      for cell in "${cells[@]}"; do
        printf 'macOS %s  %-28s %s\n' "$os" "$cell" "$(grep -h '^RESULT' "$OUT/$os-$cell.log" 2>/dev/null || echo 'RESULT missing')"
      done
    done
  } | tee "$OUT/summary.txt"
  echo "logs: $OUT"
  return "$failed"
}

cmd_clean() {
  local os vm
  for os in $(oses "${1:-}"); do
    for vm in $(limactl list --format '{{.Name}}' 2>/dev/null | grep -E "^(cm-$os|cmrun-$os)(-|$)"); do
      limactl delete -f "$vm" >/dev/null 2>&1
    done
  done
  rm -rf "$HOME/Library/Caches/lima/download"
  return 0
}

case "${1:-}" in
  _pristine) build_pristine "$2" ;;
  _clt) build_clt "$2" ;;
  _brew) build_brew "$2" ;;
  _cell) run_cell "$2" "$3" ;;
  bases) shift && cmd_bases "$@" ;;
  run) shift && cmd_run "$@" ;;
  clean) shift && cmd_clean "$@" ;;
  cells) for c in "${CELLS[@]}"; do echo "$c  (base cm-<os>$(base_of "$c"))"; done ;;
  status) limactl list ;;
  *) die "usage: matrix.sh bases|run|cells|status|clean (see the header)" ;;
esac
