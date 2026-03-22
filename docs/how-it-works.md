# How it works

Technical details on the ntfy-mac daemon internals.

## Streaming

ntfy-mac connects using [Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) (SSE) at `/<topics>/sse`. Messages arrive in real time. The connection is monitored via ntfy's keepalive events (sent every ~55 s) — if nothing arrives for 90 s, the connection is considered stalled and is re-established.

On reconnect, a poll request fetches any messages delivered during the gap.

## Offline handling

ntfy-mac uses `scutil --nwi` to detect whether the Mac has a network connection before counting a failure:

- **Offline** — waits 15 s and retries silently. No failure count, no alert.
- **Online but server unreachable** — applies exponential backoff (5 s → 5 min). After ~40 min of sustained failure, a macOS notification is sent. Alerts are rate-limited to once per hour.

## Notifications

Each ntfy message becomes a native macOS notification via a Swift helper app (`ntfy-notify.app`) that uses `UNUserNotificationCenter`. The helper is a minimal `.app` bundle so macOS can attribute notifications to ntfy-mac and persist permission state.

### Field mapping

| ntfy field   | macOS notification |
|-|-|
| `title`      | Title (bold). Falls back to capitalized topic name |
| `message`    | Body |
| `topic`      | Subtitle (with emoji tags if present), thread grouping |
| `priority`   | Sound, interruption level, relevance score, auto-dismiss |
| `tags`       | Rendered as emoji in the subtitle (`warning` → ⚠️, `rotating_light` → 🚨) |
| `click`      | URL opened on notification click |
| `attachment`  | Inline image (if image/* mime type) |
| `icon`       | Fallback thumbnail |
| `actions`    | Action buttons (view/http — up to 3 on macOS) |

### Priority behavior

| Priority | Sound | Interruption | Auto-dismiss | Relevance |
|-|-|-|-|-|
| 5 (urgent) | Ping | time-sensitive | never | 1.0 |
| 4 (high) | Ping | time-sensitive | never | 0.75 |
| 3 (default) | Pop | active | 7 s | 0.5 |
| 2 (low) | Tink | active | 5 s | 0.25 |
| 1 (min) | Tink | active | 3 s | 0.0 |

Priority 4–5 notifications break through Focus/Do Not Disturb. All sounds and dismiss timings are configurable via `ntfy-mac config`.

### Missed messages

When reconnecting after a gap, messages are categorized by age:

| Age of oldest missed message | Behavior |
|-|-|
| < 1 hour | Deliver each notification individually |
| 1 – 12 hours | Single summary: "N notifications while you were away" |
| > 12 hours | Silent — no notification storm |

## Deduplication

All delivered message IDs are persisted to `~/.local/share/ntfy-mac/state.json`. On restart, already-seen IDs are skipped. State is written atomically (write to `.tmp`, then rename) and cleaned on load: entries older than 48 h are dropped, capped at 1 000 entries.

## Topic auto-discovery

On startup, ntfy-mac queries the ntfy `/v1/account` endpoint to discover your subscribed topics. Topics are re-checked every 30 minutes — new subscriptions are picked up and removed ones are dropped without a restart.

You can override auto-discovery by setting `NTFY_TOPICS=topic1,topic2` as an environment variable.

## Update checks

Once per 24 h, ntfy-mac queries the GitHub Releases API. If a newer version is available:

- **Homebrew installs** — a notification appears with the upgrade command
- **curl installs** — auto-updates: downloads the new binary, replaces in-place, and launchd restarts the daemon

## Credential storage

Credentials are stored in `~/.config/ntfy-mac/config.json` (written by `ntfy-mac setup`). Environment variables `NTFY_URL` and `NTFY_TOKEN` serve as fallbacks when no config file exists.

## PID lock

A PID lock file prevents multiple daemon instances from running simultaneously. The lock is released on SIGINT/SIGTERM.
