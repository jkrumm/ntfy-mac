# ntfy-mac

Forward [ntfy](https://ntfy.sh) notifications to macOS Notification Center.

Runs as a background daemon via `brew services`. Streams messages in real time over SSE, stores credentials securely in macOS Keychain, and handles reconnects, missed messages, and offline periods gracefully.

[![Release](https://github.com/jkrumm/ntfy-mac/actions/workflows/release.yml/badge.svg)](https://github.com/jkrumm/ntfy-mac/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh)
- A running [ntfy](https://ntfy.sh) server (self-hosted or ntfy.sh)

---

## Install

```bash
brew install jkrumm/tap/ntfy-mac
ntfy-mac setup
brew services start ntfy-mac
```

That's it. Notifications from all your subscribed topics appear in Notification Center.

---

## Setup

### Interactive

```bash
ntfy-mac setup
```

Prompts for your ntfy server URL and access token, tests the connection, and saves credentials to macOS Keychain. The URL is auto-corrected if you omit the protocol (`ntfy.example.com` → `https://ntfy.example.com`).

Get your access token at `https://<your-ntfy-server>/account` → **Access Tokens**.

### Non-interactive (scripts / AI agents)

```bash
ntfy-mac setup --url https://ntfy.example.com --token <token>
```

Exits 0 on success, 1 on failure. Suitable for dotfile scripts or automated provisioning.

### Environment variables

For CI or server deployments where Keychain is unavailable:

| Variable      | Description                                       |
| ------------- | ------------------------------------------------- |
| `NTFY_URL`    | ntfy server base URL                              |
| `NTFY_TOKEN`  | ntfy access token                                 |
| `NTFY_TOPICS` | Comma-separated topic list (skips auto-discovery) |

**Credential precedence:** Keychain is always checked first. Environment variables are the fallback — used when no Keychain entry exists. This means `NTFY_URL` / `NTFY_TOKEN` cannot override credentials saved via `ntfy-mac setup`. To switch servers, run `ntfy-mac setup` again, or delete the Keychain entries:

```bash
security delete-generic-password -s ntfy-mac -a url
security delete-generic-password -s ntfy-mac -a token
```

> **Development note:** `bun src/index.ts` (interpreted mode) reads Keychain just like the compiled binary. If you ran `ntfy-mac setup`, env vars are ignored in dev mode too.

---

## Commands

```bash
ntfy-mac                  # Start the daemon (normally done via brew services)
ntfy-mac setup            # Interactive setup wizard
ntfy-mac logs             # Tail the daemon log
ntfy-mac logs --error     # Tail the error log
ntfy-mac --version        # Print version
ntfy-mac --help           # Print help
```

### Managing the service

```bash
brew services start ntfy-mac    # Start on login (recommended)
brew services stop ntfy-mac     # Stop
brew services restart ntfy-mac  # Restart after config changes
brew services list              # Check status
```

---

## How it works

### Streaming

ntfy-mac connects using [Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) (SSE) at `/<topics>/sse`. Messages arrive in real time. The connection is monitored via ntfy's keepalive events (sent every ~55 s) — if nothing arrives for 90 s, the connection is considered stalled and is re-established.

On reconnect, a poll request fetches any messages delivered during the gap.

### Offline handling

ntfy-mac uses `scutil --nwi` to detect whether the Mac has a network connection before counting a failure:

- **Offline** — waits 15 s and retries silently. No failure count, no alert.
- **Online but server unreachable** — applies exponential backoff (5 s → 5 min). After ~40 min of sustained failure, a macOS notification is sent. Alerts are rate-limited to once per hour.

### Notifications

Each message becomes a macOS notification via `osascript`:

| Field    | Source                                             |
| -------- | -------------------------------------------------- |
| Title    | `msg.title`, or topic name (capitalized) if absent |
| Subtitle | Topic name + emoji tags                            |
| Body     | `msg.message`                                      |
| Sound    | Based on priority                                  |

**Priority → sound:**

| Priority    | Sound    |
| ----------- | -------- |
| 5 — urgent  | Sosumi   |
| 4 — high    | Ping     |
| 3 — default | Pop      |
| 2 — low     | _(none)_ |
| 1 — min     | _(none)_ |

**Tags** are rendered as emoji in the subtitle (`warning` → `⚠️`, `rotating_light` → `🚨`, etc.). Unknown tags pass through as-is.

If `click` is set on a message, the URL opens in the default browser alongside the notification (http/https only).

> **Note:** The notification icon shows Terminal's icon when running interactively, or the binary's icon via brew services. Custom icons require a signed `.app` bundle and are not supported.

### Missed messages

When reconnecting after a gap, messages are categorised by age:

| Age of oldest missed message | Behaviour                                             |
| ---------------------------- | ----------------------------------------------------- |
| < 1 hour                     | Deliver each notification individually                |
| 1 – 12 hours                 | Single summary: "N notifications while you were away" |
| > 12 hours                   | Silent — no notification storm                        |

### Deduplication

All delivered message IDs are persisted to `~/.local/share/ntfy-mac/state.json`. On restart, already-seen IDs are skipped. State is written atomically (write to `.tmp`, then rename) and cleaned on load: entries older than 48 h are dropped, capped at 1 000 entries.

### Update checks

Once per 24 h, ntfy-mac queries the GitHub Releases API. If a newer version is available, a notification appears with the upgrade command.

---

## Logs

```bash
ntfy-mac logs             # Follow stdout (notifications, connection events)
ntfy-mac logs --error     # Follow stderr (errors, connection failures)
```

Normal log output looks like:

```
ntfy-mac 1.0.0 — listening on: homelab-watchdog, uptime-alerts
connected (topics: 2, since: now)
notify: [homelab-watchdog] Watchdog healthy
notify: [uptime-alerts] Service Down: jellyfin
connection closed — reconnecting
connected (topics: 2, since: mM36TQcB)
```

When something goes wrong:

```
connection error (attempt 1): ntfy SSE returned 401
reconnecting in 5s
```

---

## Troubleshooting

**No notifications appearing**

1. Check the service is running: `brew services list | grep ntfy-mac`
2. Verify notification permissions: System Settings → Notifications → ntfy-mac (set to Banners or Alerts, not Off)
3. Check logs: `ntfy-mac logs`

**Authentication failed**

Re-run `ntfy-mac setup` or set `NTFY_URL` / `NTFY_TOKEN` environment variables.

**No topics found**

Subscribe to at least one topic in the ntfy app or web UI first, or set `NTFY_TOPICS=topic1,topic2` to skip auto-discovery.

**Daemon exits immediately on launch**

Usually a network error during topic discovery. Check `ntfy-mac logs --error` and verify your ntfy server is reachable.

---

## Upgrade

```bash
brew upgrade jkrumm/tap/ntfy-mac
brew services restart ntfy-mac
```

---

## Uninstall

```bash
brew services stop ntfy-mac
brew uninstall ntfy-mac

# Remove saved credentials from Keychain
security delete-generic-password -s ntfy-mac -a url
security delete-generic-password -s ntfy-mac -a token

# Remove state file
rm -rf ~/.local/share/ntfy-mac
```

---

## Contributing

### Prerequisites

- [Bun](https://bun.sh) (`brew install bun`)
- macOS (required for Keychain and osascript)

### Setup

```bash
git clone https://github.com/jkrumm/ntfy-mac.git
cd ntfy-mac
bun install
```

### Development

```bash
bun src/index.ts setup     # Configure credentials interactively
bun src/index.ts           # Run the daemon (Ctrl+C to stop)
NTFY_DEBUG=1 bun src/index.ts  # Verbose mode: keepalives, message IDs, poll calls
bun test                   # Run unit tests
bun run validate           # Format + typecheck + lint + test
```

### Building

```bash
bun run build    # Produces dist/ntfy-mac-arm64 and dist/ntfy-mac-x64
```

Binaries are fully self-contained — no Bun runtime needed on the target machine.

### Release process

Releases are triggered manually via the **Run workflow** button in the Actions tab:

1. Go to Actions → Release → Run workflow, optionally choose a release type
2. Commit messages following [Conventional Commits](https://www.conventionalcommits.org) determine the version bump (or the chosen type overrides it)
3. A GitHub Release is created with the changelog
4. arm64 and x64 binaries are compiled and attached
5. `Formula/ntfy-mac.rb` in `jkrumm/homebrew-tap` is updated automatically with new version and sha256 checksums

---

## License

[MIT](LICENSE) — Johannes Krumm
