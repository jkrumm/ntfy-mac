# ntfy-mac

Native macOS client for ntfy servers. **1.x** (Bun/TypeScript daemon + Swift helper, in `src/`, `tests/*.ts`, `assets/`) is shipping and frozen. **2.0** is a native Swift rewrite built in waves; the plan, decisions and per-wave status live in `docs/waves/PLAN.md` (read it first, it is the source of truth for scope).

## Architecture (2.0 target)

- **One long-lived process:** `NtfyMac.app` (LSUIElement). It holds the NDJSON stream, posts notifications and writes history.
- **CLI-first:** `ntfy-mac` lives inside the bundle (`NtfyMac.app/Contents/MacOS/ntfy-mac`) and drives the same `NtfyCore`. Every setting and action works from the CLI; the UI is a convenience over it.
- **CLI ↔ app:** reads go straight to files (config, history DB read-only in WAL mode). Mutations write the config; the app watches it. App-only actions (post, ack, reconnect) go over a Unix domain socket, NDJSON, in the app support dir; the CLI launches the app via LaunchServices if it is down.
- **Secrets:** token in the Keychain (service `com.jkrumm.ntfy-mac`). 1.x stores it in plaintext in `config.json`; 2.0 migrates it on first run.
- Min macOS 15, Apple Silicon only. Ad-hoc signing through `scripts/sign.sh` (the single signing entry point; a Developer ID is a config change).

## Layout

| Path                                            | Purpose                                                                                                                      |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `Package.swift`                                 | SwiftPM: `NtfyCore` library, `ntfy-mac` CLI (`NtfyMacCLI`), `NtfyCoreTests`                                                  |
| `Sources/NtfyCore`, `Sources/NtfyMacCLI`        | Library and CLI                                                                                                              |
| `tests/NtfyCoreTests`                           | Swift Testing suites (shares `tests/` with the legacy `*.test.ts`; lowercase on purpose, the filesystem is case-insensitive) |
| `App/project.yml`                               | XcodeGen spec for the thin app target; `App/NtfyMac.xcodeproj` is generated, not committed                                   |
| `scripts/sign.sh`                               | Code signing                                                                                                                 |
| `src/`, `tests/*.ts`, `assets/`, `package.json` | Legacy 1.x. Reference for edge cases; deleted in the cutover wave only                                                       |

## Gate

`make check` = `swift-format` lint (strict) + `swift build` + `swift test` + `xcodebuild` of the app scheme (signed, bundled CLI smoke-run) + `bun run validate` while `src/` exists. CI runs the same target on a pinned runner and Xcode. Toolchain: Swift ≥ 6.2 (the mini has Xcode 27.1 / Swift 6.4; hosted CI uses Xcode 26.6). `make fmt` formats in place.

Commits: Conventional Commits (commitlint via lefthook). Releases: semantic-release via the Release workflow; do not tag or publish by hand.

## Compatibility contract (2.0 must keep, or migrate on first run)

- Config `~/.config/ntfy-mac/config.json` (`url`, `token`, `sounds`, `dismiss`, `extraTopics`); env `NTFY_URL`, `NTFY_TOKEN`, `NTFY_TOPICS`, `NTFY_DEBUG`.
- State `~/.local/share/ntfy-mac/state.json` (`lastMessageId` cursor carries over).
- Every 1.x command and flag: `setup [--url --token]`, `doctor [--json]`, `subscribe [topic|reset]`, `unsubscribe`, `config [sounds|dismiss] [show|list|set|reset]`, `notify (-m -t -p --tag --url -d | --json)`, `sounds [filter]`, `logs [--error]`, `update`, `uninstall`, `version`, `start`.
- Formula name `jkrumm/tap/ntfy-mac`; the priority mapping table in the README.
- Old artifacts removed on migration: `com.jkrumm.ntfy-mac` LaunchAgent, `homebrew.mxcl.ntfy-mac` service, `ntfy-notify.app` and its Launch Services entries.

## Dev server

A dev ntfy server (2.36.0) runs on the HomeLab, tailnet-only, for integration tests and dogfooding.

- URL: `https://<your-domain>` (the `url` field of `~/.config/ntfy-mac/config.json` on the MacBook, or the 1Password item `common/ntfy`).
- Token: `op://common/ntfy/TOKEN`. On the mini read it with `secrets-run read op://common/ntfy/TOKEN`, never bare `op`.
- Integration tests use topics prefixed `ntfy-mac-test-`.
- Never commit the real hostname or token.

## Rules

- Verify library, API and runner-image facts with `/research` or the primary docs; never from memory.
- Port 1.x edge cases from `src/` and its tests before deleting them; do not carry over the known 1.x defects listed in PLAN.md.
- Never start dev servers; launching the GUI app is only for a task that asks for it (spikes, verification). The owner validates running apps.
- Prose in README/docs follows the voice guide; no AI attribution anywhere.
