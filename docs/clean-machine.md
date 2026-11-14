# Clean-machine matrix

Proves the install channels on a Mac that has never seen ntfy-mac: the curl installer (`install.sh`, the direct download) and the Homebrew cask, each alone and both together, on macOS 15 and 26, install and upgrade. The record is `docs/waves/PLAN.md` (Wave 7). This page is how to rerun it.

```sh
scripts/clean-machine/matrix.sh cells             # the cells and the base each one needs
scripts/clean-machine/matrix.sh run all           # both macOS versions, every cell (about an hour)
scripts/clean-machine/matrix.sh run 26 direct-upgrade cask-upgrade
CM_OLD=2.0.1 CM_NEW=2.1.0 scripts/clean-machine/matrix.sh run all   # after a new release
```

Only the mini runs it (Apple Silicon, Lima 2.3 or later, macOS 26 host). Results land in `.build/clean-machine/<timestamp>/`: one log per cell, `summary.txt`, and `CHECK ok|FAIL|NOTE` lines inside each log.

## How it works

- **VMs.** Lima's macOS guests (Apple Virtualization.framework) from Apple's own IPSW, pinned and digest-checked by Lima's image template. `macos-15.yaml` and `macos-26.yaml` mount nothing from the host. The mini has no VM tool of its own besides Lima; Tart was not installed.
- **Bases.** Per macOS: `cm-<os>` (pristine, auto-login to the GUI session), `cm-<os>-clt` (plus the Command Line Tools), `cm-<os>-brew` (plus Homebrew). Each cell runs in a fresh APFS clone of its base, deleted when the cell ends, so every cell starts clean and the clone costs no disk until written. `run` builds the bases of one macOS, runs its cells and deletes its VMs before the next macOS starts (`CM_KEEP_BASES=1` keeps them for repeated runs).
- **Disk.** The mini panicked at 94% full on 2026-11-13. The driver refuses to start a VM below `CM_MIN_FREE_GIB` (40) free on the Data volume and drops the IPSW cache once a base exists. A macOS guest is about 20 GB written.
- **Slot.** Each unit that boots a VM (a base, a cell) runs inside `scripts/apple-slot.sh`, the same lock as every `xcodebuild`, so it waits for builds and builds wait for it for the length of one unit only.
- **GUI session.** Without a logged-in user there is no notification, Gatekeeper or login-item behaviour. Lima's guests start at the login window; the driver writes `/etc/kcpassword` and the auto-login preference (`sysadminctl -autologin` fails headless) and reboots once.

## What a script can and cannot judge

A prompt is a window of some owner: `windows.js` lists the owners on screen (`CoreServicesUIAgent` for the Gatekeeper and "install developer tools" dialogs), and the notification permission request is a `usernoted` log line (`Sending request for permission for com.jkrumm.ntfy-mac`). So "no unexpected prompt" and "exactly one permission request on first launch" are checked.

Nothing in a guest can click: the Accessibility and Automation grants need a click, `TCC.db` and the notification database are protected, and the host has no Accessibility trust. Three consequences:

- The notification permission can never be **allowed** in a guest. The first launch ends in `denied`, so "permission kept across an upgrade" is checked as "same state, no new request"; that the **allowed** state survives is on the owner checklist (PLAN, Wave 7).
- The Sparkle approval dialog cannot be answered. The cell checks `update --check` and that the prompt window appears; the click and relaunch were proven on the MacBook (Issue 1045).
- A Homebrew install is quarantined, so macOS asks once before it opens the app (`cask-first-launch` records it). Every other cask cell approves the download the way the click does: it replaces the bundle by a copy without the flag (`xattr -d` is refused on an app in `/Applications`, even for root).

## The cask

The production tap still carries the formula; the cask goes live with the next Release run (AGENTS.md "Release process"). The cells install a cask rendered by `scripts/render-cask.sh` from the published `NtfyMac-<version>.zip` and its `SHA256SUMS`, from a local tap in the guest (`local/cm`). That is the file the tap job renders, so what is exercised is the cask, not the tap's git remote.

## Data

`fake-ntfy.py` is a minimal ntfy server on `127.0.0.1` in the guest (an account probe and three messages per topic). A cell writes a 1.x-style `config.json` (plaintext token, `allowInsecure`), so the first launch also moves the token into the Keychain and the app builds a history of three messages: the config hash, the history count, the Keychain item, the recorded team pin and the permission state are compared across an upgrade. `ntfy-mac setup` is not used, because it refuses without notification permission.
