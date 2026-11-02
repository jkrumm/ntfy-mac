# ntfy-mac

Native macOS notifications for your [ntfy](https://ntfy.sh) server.

Runs as a background app that streams messages in real time, handles reconnects and offline periods, and delivers notifications through macOS Notification Center — with full support for all ntfy message features including priorities, tags, action buttons, images, and click URLs. The same binary is a CLI built for scripts and AI agents: JSON output, stable exit codes, and a command that blocks until a human replies.

[![Release](https://github.com/jkrumm/ntfy-mac/actions/workflows/release.yml/badge.svg)](https://github.com/jkrumm/ntfy-mac/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<!-- screenshot placeholder -->

---

## Why ntfy-mac?

ntfy doesn't ship a native desktop client. The [recommended approach](https://docs.ntfy.sh/subscribe/pwa/) for desktop is a PWA — a browser tab that stays open and forwards notifications. In practice, this doesn't work reliably on macOS:

- Notifications stop when the browser is quit, restarted, or updated
- Background tabs get suspended — messages arrive late or not at all
- No integration with Focus mode or Do Not Disturb
- No way to recover messages missed while offline or asleep
- Duplicate notifications when reconnecting

ntfy-mac is a native app that holds the stream open, starts at login (`ntfy-mac login-item on`), recovers missed messages on reconnect, and deduplicates everything. It delivers through macOS Notification Center with proper priority mapping — urgent messages break through Focus mode, low-priority ones auto-dismiss.

It's been running stable for months with zero missed notifications across sleep/wake cycles, network changes, and server restarts.

---

## Install

Requires macOS (Apple Silicon) and a running [ntfy](https://ntfy.sh) server.

### Homebrew (recommended)

```bash
brew install jkrumm/tap/ntfy-mac
ntfy-mac setup
```

### curl (one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/jkrumm/ntfy-mac/master/install.sh | bash
ntfy-mac setup
```

The daemon starts on login automatically after installation.

> Install paths change with 2.0, which ships `NtfyMac.app` instead of a daemon; the steps above describe 1.x.

---

## Features

**Reliable real-time delivery** — SSE streaming with automatic reconnect, offline detection, and missed-message recovery. Notifications are paced to ensure every message gets a visible banner, even during bursts. No polling, no missed alerts.

**Full ntfy support** — Priorities, emoji tags, titles, images, click-to-open URLs, and action buttons (view/http) — all mapped to native macOS notification capabilities.

**Priority-aware** — Each priority level has its own sound, interruption level, and auto-dismiss timing. Urgent and high priority notifications break through Focus and Do Not Disturb.

**Configurable** — Customize sounds and auto-dismiss timing per priority level. Preview all macOS sounds from the CLI. Add your own sounds to `~/Library/Sounds/`.

**Auto-discovery** — Picks up your subscribed topics automatically. Re-checks every 30 minutes — no restart needed when you add or remove topics.

**Self-updating** — Checks for updates daily and notifies you or updates automatically.

**Diagnostics** — `ntfy-mac doctor` checks config, server, auth, the app, notification permissions, the login item, and the history in one read-only command. `--send-test` posts a test notification.

**Agent-ready** — Every command takes `--json`. Exit codes are stable, errors have codes, and `ntfy-mac schema --json` describes the whole CLI. See [Use from agents and scripts](#use-from-agents-and-scripts).

---

## Setup

```bash
ntfy-mac setup
```

Prompts for your ntfy server URL and access token, tests the connection, and saves the config. The token goes to the Keychain.

Get your access token at `https://<your-ntfy-server>/account` → **Access Tokens**.

For scripts or automation:

```bash
ntfy-mac setup --url https://ntfy.example.com --token tk_...
```

---

## Commands

| Command                | Description                                                       |
| ---------------------- | ----------------------------------------------------------------- |
| `ntfy-mac setup`       | Connect ntfy-mac to your ntfy server.                             |
| `ntfy-mac doctor`      | Check configuration, server, app and permissions.                 |
| `ntfy-mac subscribe`   | Show the subscribed topics, add a local one, or reset.            |
| `ntfy-mac unsubscribe` | Remove a locally added topic.                                     |
| `ntfy-mac config`      | Show and change notification settings.                            |
| `ntfy-mac notify`      | Send a local notification through the app (no server needed).     |
| `ntfy-mac sounds`      | Preview the notification sounds.                                  |
| `ntfy-mac logs`        | Show the app's log from the unified log.                          |
| `ntfy-mac update`      | Update ntfy-mac (Homebrew installs) or check for a newer release. |
| `ntfy-mac uninstall`   | Remove ntfy-mac's config, history, state and token.               |
| `ntfy-mac version`     | Print the version.                                                |
| `ntfy-mac start`       | Start the ntfy-mac app if it is not running.                      |
| `ntfy-mac status`      | Show the connection, pause, permissions and history counts.       |
| `ntfy-mac ls`          | List messages from the history, newest first.                     |
| `ntfy-mac search`      | Search the history by text, newest first.                         |
| `ntfy-mac read`        | Show one message in full and mark it read.                        |
| `ntfy-mac ack`         | Acknowledge a message, or every unacknowledged one.               |
| `ntfy-mac tail`        | Print messages as NDJSON, optionally following new ones.          |
| `ntfy-mac wait`        | Block until a matching message arrives.                           |
| `ntfy-mac publish`     | Publish a message to a topic on the ntfy server.                  |
| `ntfy-mac pause`       | Hold notifications back for a while.                              |
| `ntfy-mac resume`      | End a pause and show what was held back.                          |
| `ntfy-mac login-item`  | Start ntfy-mac at login: on, off or status.                       |
| `ntfy-mac schema`      | Describe every command, flag, exit code and error code.           |

---

## Notification sounds

Default sounds per priority:

| Priority    | Sound | Focus mode     | Auto-dismiss |
| ----------- | ----- | -------------- | ------------ |
| 5 (urgent)  | Ping  | breaks through | stays        |
| 4 (high)    | Ping  | breaks through | stays        |
| 3 (default) | Pop   | normal         | 8 s          |
| 2 (low)     | Tink  | normal         | 5 s          |
| 1 (min)     | Tink  | normal         | 4 s          |

Override any of these:

```bash
ntfy-mac config sounds set 5 Sosumi    # Change urgent sound
ntfy-mac config sounds set 2 silent    # Make low-priority silent
ntfy-mac config dismiss set 3 15       # Default priority stays 15 s
ntfy-mac config dismiss set 5 never    # Urgent never auto-dismisses
ntfy-mac sounds                        # Preview all available sounds
```

Custom sounds can be added to `~/Library/Sounds/` (AIFF/WAV/CAF format).

The running app watches the config file, so changes apply without a restart.

---

## Local notifications

Post a notification from the command line — no ntfy server involved. The app shows it, and `notify` starts the app if it is down. Without notification permission it exits 4. Useful for shell scripts, cron jobs, CI pipelines, or AI coding agent hooks.

```bash
ntfy-mac notify -m "Deploy complete"
ntfy-mac notify -t "Alert" -m "Disk usage above 90%" -p 5
ntfy-mac notify -m "Build passed" --tag white_check_mark
ntfy-mac notify -m "Click me" --url https://example.com
ntfy-mac notify -m "Temporary" -d 10                        # dismiss after 10s
echo '{"title":"T","body":"B"}' | ntfy-mac notify --json    # full payload via stdin
```

---

## Use from agents and scripts

`ntfy-mac` is built to be driven by a program: every command takes `--json`, exit codes are stable, and prompts appear only on a terminal.

```bash
ntfy-mac status --json                        # configured? app running? paused? counts
ntfy-mac publish builds -m "Deploy v2?" -p 4  # send to your ntfy server
ntfy-mac wait --topic builds --match '/^(yes|no)/i' --timeout 600 --json
ntfy-mac tail --topic alerts --follow         # NDJSON, one message per line
ntfy-mac ack --all --topic alerts             # clear what you have handled
```

**JSON mode.** With `--json`, stdout carries JSON and nothing else: one document per command, one per line for `tail`. Diagnostics, progress and prompts go to stderr in both modes. A failure prints `{"error":{"code":"not-found","exitCode":1,"message":"..."}}` on stdout and `Error: ...` on stderr, so branch on `error.code`.

**Exit codes.**

| Code | Meaning                                            |
| ---- | -------------------------------------------------- |
| 0    | Done                                               |
| 1    | Runtime failure; the error code says which         |
| 2    | Invalid flags or values; nothing was done          |
| 3    | The server rejected the token                      |
| 4    | The app is not running, or a permission is missing |
| 7    | The ntfy server is unreachable                     |

**Wait for a human.** `wait` blocks until a message on the topic matches a substring or a `/regex/`, then prints it and exits 0. No match within `--timeout` seconds exits 1 with the error code `timeout`. Only messages that arrive after `wait` started count, so pick a pattern your own published message does not match. `--ack` acknowledges the match through the app.

**Read the history.** `ls`, `search`, `read` and `tail` read the history database directly, so they work while the app is down; they just see nothing new. `tail` always prints NDJSON, oldest first. `read` marks a message read unless you pass `--no-mark`.

**Check before you act.** `status` reports `configured`, `running`, `paused` and the permission state without changing anything. `doctor` is the full read-only check and exits non-zero when one fails.

**Discover the CLI.** `ntfy-mac schema --json` prints the command tree on one line: arguments with type, default, range and repeatability, what each command needs from the app and the server, and its error codes. The same data, rendered, lives in [docs/cli.md](docs/cli.md) and [llms.txt](llms.txt). Both are generated and checked in CI; do not edit them by hand.

---

## Troubleshooting

**No notifications appearing**

1. Check permissions: System Settings → Notifications → ntfy-mac → Allow Notifications
2. Check notification style: must be set to **Banners** or **Alerts** (not "None")
3. Check logs: `ntfy-mac logs`

**Sounds play but no banners visible**

1. Disable **Scheduled Summary**: System Settings → Notifications → ntfy-mac → turn off "Scheduled Summary" (Mitteilungen zusammenfassen). macOS silently queues notifications to Notification Center when this is enabled
2. Check **Focus mode**: ensure ntfy-mac is not being filtered. High-priority notifications (p4/p5) use `time-sensitive` interruption level and should break through Focus, but lower priorities may be suppressed

**Authentication failed** — Re-run `ntfy-mac setup`.

**No topics found** — Subscribe to at least one topic in the ntfy web UI or app first.

**Full health check** — Run `ntfy-mac doctor` to validate everything at once. It checks notification permissions, server connectivity, whether the app runs, and more.

---

## Update & uninstall

```bash
ntfy-mac update       # Upgrades a Homebrew install; --check only looks for a new release
ntfy-mac uninstall    # Removes config, history, state and the token
```

---

## Documentation

- [How it works](docs/how-it-works.md) — streaming, reconnect, dedup, missed messages, priority mapping
- [CLI reference](docs/cli.md) — every command, flag, exit code and error code (generated)
- [llms.txt](llms.txt) — the same for agents, with the JSON and NDJSON contracts
- [Contributing](docs/contributing.md) — development setup, building, release process

## License

[MIT](LICENSE) — Johannes Krumm
