# ntfy-mac

Native macOS notifications for your [ntfy](https://ntfy.sh) server.

Runs as a background daemon that streams messages in real time, handles reconnects and offline periods, and delivers notifications through macOS Notification Center — with full support for all ntfy message features including priorities, tags, action buttons, images, and click URLs.

[![Release](https://github.com/jkrumm/ntfy-mac/actions/workflows/release.yml/badge.svg)](https://github.com/jkrumm/ntfy-mac/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<!-- screenshot placeholder -->

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

---

## Features

**Real-time delivery** — SSE streaming with automatic reconnect, offline detection, and missed-message recovery. No polling, no delays.

**Full ntfy support** — Priorities, emoji tags, titles, images, click-to-open URLs, and action buttons (view/http) — all mapped to native macOS notification capabilities.

**Priority-aware** — Each priority level has its own sound, interruption level, and auto-dismiss timing. Urgent and high priority notifications break through Focus and Do Not Disturb.

**Configurable** — Customize sounds and auto-dismiss timing per priority level. Preview all macOS sounds from the CLI. Add your own sounds to `~/Library/Sounds/`.

**Auto-discovery** — Picks up your subscribed topics automatically. Re-checks every 30 minutes — no restart needed when you add or remove topics.

**Self-updating** — Checks for updates daily and notifies you or updates automatically.

**Diagnostics** — `ntfy-mac doctor` validates config, server connectivity, auth, daemon status, and logs in one command.

---

## Setup

```bash
ntfy-mac setup
```

Prompts for your ntfy server URL and access token, tests the connection, and saves the config.

Get your access token at `https://<your-ntfy-server>/account` → **Access Tokens**.

For scripts or automation:

```bash
ntfy-mac setup --url https://ntfy.example.com --token tk_...
```

---

## Commands

| Command | Description |
|-|-|
| `ntfy-mac setup` | Configure server and credentials |
| `ntfy-mac doctor` | Health check (config, server, auth, daemon, logs) |
| `ntfy-mac config` | Show notification settings |
| `ntfy-mac config sounds` | Manage sounds per priority |
| `ntfy-mac config dismiss` | Manage auto-dismiss timing per priority |
| `ntfy-mac notify -m "text"` | Send a local notification (no server needed) |
| `ntfy-mac sounds` | Preview all macOS notification sounds |
| `ntfy-mac logs` | Tail the daemon log |
| `ntfy-mac logs --error` | Tail the error log |
| `ntfy-mac update` | Update to the latest version |
| `ntfy-mac uninstall` | Remove ntfy-mac and all its data |

---

## Notification sounds

Default sounds per priority:

| Priority | Sound | Focus mode | Auto-dismiss |
|-|-|-|-|
| 5 (urgent) | Ping | breaks through | stays |
| 4 (high) | Ping | breaks through | stays |
| 3 (default) | Pop | normal | 7 s |
| 2 (low) | Tink | normal | 5 s |
| 1 (min) | Tink | normal | 3 s |

Override any of these:

```bash
ntfy-mac config sounds set 5 Sosumi    # Change urgent sound
ntfy-mac config sounds set 2 silent    # Make low-priority silent
ntfy-mac config dismiss set 3 15       # Default priority stays 15 s
ntfy-mac config dismiss set 5 never    # Urgent never auto-dismisses
ntfy-mac sounds                        # Preview all available sounds
```

Custom sounds can be added to `~/Library/Sounds/` (AIFF/WAV/CAF format).

Changes take effect after `brew services restart ntfy-mac`.

---

## Local notifications

Send notifications directly from the command line — no server required. Useful as a notification interface for shell scripts, cron jobs, CI pipelines, or AI coding agents like Claude Code hooks.

```bash
ntfy-mac notify -m "Deploy complete"
ntfy-mac notify -t "Alert" -m "Disk usage above 90%" -p 5
ntfy-mac notify -m "Build passed" --tag white_check_mark
ntfy-mac notify -m "Click me" --url https://example.com
ntfy-mac notify -m "Temporary" -d 10                        # dismiss after 10s
echo '{"title":"T","body":"B"}' | ntfy-mac notify --json    # full payload via stdin
```

---

## Troubleshooting

**No notifications appearing**
1. Check notification permissions: System Settings → Notifications → ntfy-mac
2. Check logs: `ntfy-mac logs`

**Authentication failed** — Re-run `ntfy-mac setup`.

**No topics found** — Subscribe to at least one topic in the ntfy web UI or app first.

**Full health check** — Run `ntfy-mac doctor` to validate everything at once.

---

## Update & uninstall

```bash
ntfy-mac update       # Works for both Homebrew and curl installs
ntfy-mac uninstall    # Removes binary, config, state, and daemon
```

---

## Documentation

- [How it works](docs/how-it-works.md) — streaming, reconnect, dedup, missed messages, priority mapping
- [Contributing](docs/contributing.md) — development setup, building, release process

## License

[MIT](LICENSE) — Johannes Krumm
