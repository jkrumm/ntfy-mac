# ntfy-mac

Forward [ntfy](https://ntfy.sh) notifications to macOS Notification Center.

Runs as a background daemon via `brew services`. Streams messages in real time over SSE, stores credentials securely in macOS Keychain, and handles missed messages gracefully after reconnects — showing individual notifications, a summary, or staying silent depending on how long you were away.

[![Release](https://github.com/jkrumm/homebrew-ntfy-mac/actions/workflows/release.yml/badge.svg)](https://github.com/jkrumm/homebrew-ntfy-mac/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh)
- A running [ntfy](https://ntfy.sh) server (self-hosted or ntfy.sh)

---

## Install

```bash
brew install jkrumm/ntfy-mac/ntfy-mac
ntfy-mac setup
brew services start ntfy-mac
```

That's it. Notifications from all your subscribed topics will appear in Notification Center.

---

## Configure

Run the interactive setup wizard:

```bash
ntfy-mac setup
```

You will be prompted for:

| Prompt          | Description                                                   |
| --------------- | ------------------------------------------------------------- |
| ntfy server URL | Base URL of your ntfy server, e.g. `https://ntfy.example.com` |
| Auth token      | Your ntfy access token (input is hidden)                      |

On success, credentials are saved to macOS Keychain under the service name `ntfy-mac`. Topics are discovered automatically from your account subscriptions.

### Environment variable overrides

For CI or server deployments where Keychain is unavailable:

| Variable      | Description                                       |
| ------------- | ------------------------------------------------- |
| `NTFY_URL`    | ntfy server base URL                              |
| `NTFY_TOKEN`  | ntfy access token                                 |
| `NTFY_TOPICS` | Comma-separated topic list (skips auto-discovery) |

Environment variables take precedence over Keychain when Keychain is unavailable.

---

## Usage

```bash
ntfy-mac setup        # Run the setup wizard
ntfy-mac              # Start the daemon (usually via brew services)
ntfy-mac --version    # Print version
```

### As a background service

```bash
brew services start ntfy-mac    # Start on login
brew services stop ntfy-mac     # Stop
brew services restart ntfy-mac  # Restart after config changes
```

---

## How it works

### Streaming

ntfy-mac connects to your ntfy server using [Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) (SSE). Messages arrive in real time without polling. On connection drops, it falls back to a JSON polling request, then reconnects with exponential backoff (5 s → 10 s → … → 5 min cap).

### Notifications

Each message is delivered to macOS Notification Center via `osascript`. Notification fields:

| Field    | Source                                             |
| -------- | -------------------------------------------------- |
| Title    | `msg.title`, or topic name (capitalized) if absent |
| Subtitle | Topic name + emoji tags (if any)                   |
| Body     | `msg.message`                                      |
| Sound    | Based on priority (see below)                      |

**Priority → sound mapping:**

| Priority    | Sound    |
| ----------- | -------- |
| 5 — urgent  | Sosumi   |
| 4 — high    | Ping     |
| 3 — default | Pop      |
| 2 — low     | _(none)_ |
| 1 — min     | _(none)_ |

If `msg.click` is set, the URL is opened in the default browser alongside the notification.

### Missed messages

When the daemon reconnects after a gap, it polls for messages missed during the outage and categorises them:

| Age of oldest missed message | Behaviour                                             |
| ---------------------------- | ----------------------------------------------------- |
| < 1 hour                     | Deliver each notification individually                |
| 1 – 12 hours                 | Single summary: "N notifications while you were away" |
| > 12 hours                   | Silent — no notification storm                        |

### Deduplication

All delivered message IDs are persisted to `~/.local/share/ntfy-mac/state.json`. On restart, already-seen IDs are skipped. The state file is written atomically (tmp → rename) and cleaned up on load: entries older than 48 hours are dropped, and the list is capped at 1 000 entries.

### Update checks

Once per 24 hours, ntfy-mac silently queries the GitHub Releases API. If a newer version is available, a macOS notification appears with the upgrade command.

---

## Upgrade

```bash
brew upgrade jkrumm/ntfy-mac/ntfy-mac
brew services restart ntfy-mac
```

---

## Uninstall

```bash
brew services stop ntfy-mac
brew uninstall ntfy-mac

# Optional: remove saved credentials from Keychain
security delete-generic-password -s ntfy-mac -a url
security delete-generic-password -s ntfy-mac -a token

# Optional: remove state file
rm -rf ~/.local/share/ntfy-mac
```

---

## Troubleshooting

### Logs

```bash
tail -f $(brew --prefix)/var/log/ntfy-mac.log
tail -f $(brew --prefix)/var/log/ntfy-mac-error.log
```

### Common issues

**No notifications appearing**

- Check the daemon is running: `brew services list | grep ntfy-mac`
- Verify macOS Notification Center permissions for `ntfy-mac` in System Settings → Notifications
- Check the log for errors

**Authentication failed**

- Re-run `ntfy-mac setup` with a valid token
- Or set `NTFY_URL` / `NTFY_TOKEN` environment variables

**No topics found**

- Subscribe to at least one topic in the ntfy app or web UI first
- Or set `NTFY_TOPICS=topic1,topic2` to skip auto-discovery

**Notifications stop after a while**

- macOS may have killed the service. Run `brew services restart ntfy-mac`
- The daemon uses exponential backoff on errors — check logs for repeated failures

---

## Contributing

### Prerequisites

- [Bun](https://bun.sh) (`brew install bun`)
- macOS (required for Keychain and osascript)

### Setup

```bash
git clone https://github.com/jkrumm/homebrew-ntfy-mac.git
cd homebrew-ntfy-mac
bun install
```

### Development

```bash
bun run start          # Run the daemon directly (requires ntfy-mac setup first)
bun test               # Run unit tests
bun run validate       # Format check + typecheck + lint + test
```

### Building

```bash
bun run build          # Build both arm64 and x64 binaries to dist/
```

Binaries are fully self-contained — no Bun runtime needed on the target machine.

### Release process

Releases are fully automated via semantic-release on every push to `master`:

1. Commit messages following [Conventional Commits](https://www.conventionalcommits.org) determine the next version
2. A GitHub Release is created with the changelog
3. arm64 and x64 binaries are compiled and uploaded as release assets
4. `Formula/ntfy-mac.rb` is automatically updated with the new version and sha256 checksums

---

## License

[MIT](LICENSE) — Johannes Krumm
