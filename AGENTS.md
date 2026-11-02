# ntfy-mac

Native macOS client for ntfy servers. **1.x** (Bun/TypeScript daemon + Swift helper, in `src/`, `tests/*.ts`, `assets/`) is shipping and frozen. **2.0** is a native Swift rewrite built in waves; the plan, decisions and per-wave status live in `docs/waves/PLAN.md` (read it first, it is the source of truth for scope).

## Architecture (2.0 target)

- **One long-lived process:** `NtfyMac.app` (LSUIElement). It holds the NDJSON stream, posts notifications and writes history.
- **CLI-first:** `ntfy-mac` lives inside the bundle (`NtfyMac.app/Contents/MacOS/ntfy-mac`) and drives the same `NtfyCore`. Every setting and action works from the CLI; the UI is a convenience over it.
- **CLI ↔ app:** reads go straight to files (config, history DB read-only in WAL mode). Mutations write the config; the app watches it. App-only actions (post, ack, reconnect) go over a Unix domain socket, NDJSON, in the app support dir; the CLI launches the app via LaunchServices if it is down.
- **Secrets:** token in the Keychain (service `com.jkrumm.ntfy-mac`). 1.x stores it in plaintext in `config.json`; 2.0 migrates it on first run.
- Min macOS 15, Apple Silicon only. Ad-hoc signing through `scripts/sign.sh` (the single signing entry point; a Developer ID is a config change).

## Layout

Dependency direction is enforced in `Package.swift`. `NtfyCore` depends on nothing; every adapter sees the core and nothing else; executables are the only composition roots.

| Path                                            | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Sources/NtfyCore`                              | Pure domain and policy, no I/O: messages, priority mapping, errors, config model and token migration, `MissedMessagePolicy`, `ReconnectMachine`, `StreamSupervisor`, `DeliveryService` (paced queue, retries, auto-dismiss, re-alert, reminders, boot reconcile), and the ports (`Clock`, `MessageStream`, `MessagePoller`, `TopicSource`, `CursorStore`, `SystemEvents`, `SecretStore`, `NotificationPoster`, `Delivering`, `HistoryStore`, `HistoryInbox`, `ConfigStore`, `NtfyPublishing`, `LoginItemControlling`) |
| `Sources/NtfyClient`                            | HTTP adapters: NDJSON stream, catch-up poller, account topics; https-only tokens unless `allowInsecure`                                                                                                                                                                                                                                                                                                                                                                                                               |
| `Sources/NtfyStore`                             | History store adapter (GRDB, SQLite WAL, FTS5)                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `Sources/NtfyPlatform`                          | Keychain, config and 1.x state files (atomic writes), config watcher, wake and path monitor, `os.Logger` helper; the only module that imports UserNotifications: `NotificationCenterClient` (live and fake), `UserNotificationPoster`, `UserNotificationPermissionProvider`, `NotificationResponder`; `SMAppServiceLoginItem` (the app's own login item)                                                                                                                                                              |
| `Sources/NtfyIPC`                               | Versioned Codable socket protocol (NDJSON)                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `Sources/NtfyTesting`                           | In-memory fakes for every port; linked by test targets only                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `Sources/NtfyMacCLI`                            | `ntfy-mac` CLI; typed errors map to exit codes only here (0 ok, 1 runtime, 2 usage, 3 auth, 4 app/permission unavailable, 7 server unreachable)                                                                                                                                                                                                                                                                                                                                                                       |
| `App/`                                          | XcodeGen spec (`project.yml`) and SwiftUI app sources; `App/NtfyMac.xcodeproj` is generated, not committed. `App/Sources` is the app composition root and the only place real adapters meet: `AppController` (config reload, permission, launch) builds and tears down an `AppPipeline` (store, delivery, responses, stream); `PipelineReload` in the core decides when                                                                                                                                               |
| `tests/<Target>Tests`                           | Swift Testing suites (`tests/` is shared with the legacy `*.test.ts`; lowercase on purpose, the filesystem is case-insensitive)                                                                                                                                                                                                                                                                                                                                                                                       |
| `scripts/tools.sh`                              | Pinned, SHA-256-verified tool binaries in `.tools/` (SwiftLint, Periphery, XcodeGen)                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `scripts/sign.sh`                               | Code signing, the single entry point                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `src/`, `tests/*.ts`, `assets/`, `package.json` | Legacy 1.x. Reference for edge cases; deleted in the cutover wave only                                                                                                                                                                                                                                                                                                                                                                                                                                                |

Rules: actors own mutable state (stream supervisor, delivery queue); no singletons or global state; one composition root each in the app and the CLI; logging via `os.Logger` (subsystem `com.jkrumm.ntfy-mac`, categories per area); tests go through module interfaces, not internals.

## Gate

`make check` = `toolchain` + `lint-format` (`swift format lint --strict`) + `lint` (pinned SwiftLint `--strict`) + `build` (warnings are errors for our targets) + `test` (Swift Testing) + `app` (xcodebuild, ad-hoc sign, bundled CLI smoke-run) + `legacy` (`bun run validate` while `src/` exists). CI runs the same target on a pinned runner and Xcode. `make format` writes formatting; `make analyze` runs Periphery and joins the gate once the tree is clean; `make install-macbook` installs the signed build into `~/Applications` on the MacBook over `ssh iumac` (never launches it).

Toolchain: Swift ≥ 6.2 (the mini has Xcode 27.1 / Swift 6.4; hosted CI uses Xcode 26.6). Tool versions are pinned and verified with `/research`; never use `brew` for the pinned tools.

Human checks: never ask the owner to look at the mini's screen. Install on the MacBook (`make install-macbook`), batch the checks into one checklist per wave, and name the machine in every step.

Commits: Conventional Commits (commitlint via lefthook; the pre-commit hook lints staged Swift). Releases: semantic-release via the Release workflow; do not tag or publish by hand.

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
