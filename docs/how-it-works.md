# How it works

One app holds the connection and the history. The CLI is a second front end over the same core. This page covers the moving parts; the code layout is in `AGENTS.md`.

## App and CLI

`NtfyMac.app` is a menu bar app with no Dock icon. It is the only long-lived process: it holds the stream, posts notifications and writes the history. The `ntfy-mac` CLI lives inside the bundle at `NtfyMac.app/Contents/MacOS/ntfy-mac`; Homebrew and `install.sh` link it onto your PATH. The CLI never holds a connection.

- **Reads** (`ls`, `search`, `read`, `tail`, `wait`, `status`) go straight to the config and the history database, which is SQLite in WAL mode, so they work while the app is down. `tail --follow` and `wait` poll the database every 500 ms.
- **Writes to state** (`config`, `subscribe`, `pause`, `resume`) edit the config file. The app watches it and applies the change, so it need not be reachable. `pause` stores `pausedUntil`; with no flags that is 2100-01-01 until `resume`. Held-back messages are stored and shown when the pause ends.
- **Read marks:** `read` marks a message read by writing to the history database itself (`--no-mark` skips it). Acknowledging goes through the app, because it has to withdraw the notification and stop the re-alerts.
- **App-only actions** (`ack`, `remind`, `delete`, `notify`, `login-item`, and the live state in `status` and `doctor`) go over a Unix domain socket in the app support directory, NDJSON. The CLI starts the app through LaunchServices when the command needs it and it is down.
- **Contract:** every command, flag, exit code and error code is in the generated [CLI reference](cli.md).

## Streaming

The app connects to `/<topics>/json` and reads the NDJSON stream with `URLSession`. A reconnect state machine with an injectable clock drives it:

- **Backoff** doubles from a short first delay up to 5 minutes, scaled by jitter into 50 to 100 percent. It resets only after a connection stayed up for 60 seconds, so a server that accepts and drops does not reset it.
- **Watchdog.** If nothing arrives (message or keepalive) for twice the observed keepalive gap, at least 90 seconds, the connection counts as stalled and is replaced.
- **Terminal answers.** A 401 or 403, or a redirect, stops the stream: the token is never sent to another host. A 429 waits long.
- **Wake and network changes.** The app reconnects when the Mac wakes or the network path changes, without waiting for the watchdog.
- **Offline.** While there is no network path, the app waits instead of counting failures.

After every reconnect a poll request fetches what arrived during the gap. The cursor (`lastMessageId`, in `~/.local/share/ntfy-mac/state.json`) advances only after a message is stored.

## History and deduplication

Every message goes into the history database (GRDB over SQLite, WAL mode, mode 600) before it is shown. The key is `(server, topic, id)` and the insert ignores duplicates, so a replay after a reconnect, or a poll that overlaps the stream, creates no second row or notification. FTS5 powers search. Retention is per topic and pruning runs on a timer, not only at launch.

`message_delete` and `message_clear` events withdraw the stored message and its notification. A message with a `sequence_id` replaces the earlier one.

## Notifications

Delivery goes through one paced queue: sends are at least 1.5 seconds apart so macOS does not drop banners in a burst, higher priorities drain first, and failed posts are retried. The app posts through `UNUserNotificationCenter` as `com.jkrumm.ntfy-mac`; permission is per bundle id.

### Field mapping

| ntfy field   | macOS notification                                         |
| ------------ | ---------------------------------------------------------- |
| `title`      | Title. Falls back to the topic name                        |
| `message`    | Body                                                       |
| `topic`      | Subtitle (with emoji tags if present), thread grouping     |
| `priority`   | Sound, interruption level, relevance score, auto-dismiss   |
| `tags`       | Emoji in the subtitle (`warning` is a warning sign)        |
| `click`      | URL opened on click, limited to allowed schemes            |
| `attachment` | Inline image for `image/*`; other types in the History window |
| `icon`       | Thumbnail                                                  |
| `actions`    | Buttons for `view` and `http`, plus Acknowledge            |

Icons and attachments are fetched with a size cap, without redirects, and the token is sent only to the server's own origin.

### Priority behavior

| Priority    | Sound | Interruption   | Auto-dismiss | Relevance |
| ----------- | ----- | -------------- | ------------ | --------- |
| 5 (urgent)  | Ping  | time-sensitive | never        | 1.0       |
| 4 (high)    | Ping  | time-sensitive | never        | 0.75      |
| 3 (default) | Pop   | active         | 8 s          | 0.5       |
| 2 (low)     | Tink  | active         | 5 s          | 0.25      |
| 1 (min)     | Tink  | active         | 4 s          | 0.0       |

The time-sensitive level needs a restricted entitlement (`com.apple.developer.usernotifications.time-sensitive`, which needs a provisioning profile; a Developer ID release embeds it). The app reads its own entitlements at run time: with it, priorities 4 and 5 use the time-sensitive level; without it (an ad-hoc build) they degrade to the active level, so they are loud but may not break through every Focus. Sounds and dismiss times are configurable (`ntfy-mac config`). Urgent and high notifications repeat until acknowledged when `reAlert` is on.

### Missed messages

When the app reconnects after a gap, it sorts the batch by the age of its oldest message:

| Age of oldest missed message | Behavior                                              |
| ---------------------------- | ----------------------------------------------------- |
| under 1 hour                 | Each message gets its own notification                |
| 1 to 12 hours                | One summary: "N notifications while you were away"    |
| over 12 hours                | Stored only, no notification                          |

## Topics

The app asks `/v1/account` for the topics you subscribe to and re-checks every 30 minutes. `NTFY_TOPICS` or `ntfy-mac subscribe` adds local ones. Muted topics are stored and never notify; a per-topic minimum priority holds quieter messages back.

## Credentials

The server URL lives in `~/.config/ntfy-mac/config.json`. The token lives in the Keychain (service `com.jkrumm.ntfy-mac`). `NTFY_URL` and `NTFY_TOKEN` serve as fallbacks when nothing is configured.

## First run after 1.x

On launch the app checks for 1.x leftovers and removes them: the `com.jkrumm.ntfy-mac` LaunchAgent, the `homebrew.mxcl.ntfy-mac` service, the running daemon, `ntfy-notify.app` and its Launch Services entries, the old binary and logs. `config.json` and `state.json` stay. A plaintext token in `config.json` moves to the Keychain. `ntfy-mac migrate` does the same by hand; `--dry-run` lists what it would remove.

## Updates

Release assets are `ntfy-mac-<version>-arm64.tar.gz` (install.sh), `NtfyMac-<version>.zip` (Sparkle and the Homebrew cask) and `appcast.xml` (Sparkle) and `SHA256SUMS`. The app is Developer ID signed, notarized and stapled; `install.sh` checks the SHA-256 and that signature state before it touches an existing install.

A direct copy, and the Homebrew cask copy, update through Sparkle inside the app. The cask declares `auto_updates true`, yet on Homebrew 7.0.13 a bare `brew upgrade` still moves a cask copy whose app is older than the tap; it skips one that is already at the tap's version, whoever put it there. `ntfy-mac update` asks the running app over the socket: `--check` looks without a window, otherwise the app opens Sparkle's prompt. Sparkle accepts an update only with a valid EdDSA signature or the same code-signing identity, and refuses downgrades. It has no Team ID pin, so the app records the Team ID of its first Developer-ID-signed run (`team-pin` in the app support directory) and turns the updater off for a build signed by another team. An old Homebrew formula copy (under the Cellar), an ad-hoc development build and `NTFY_MAC_NO_SELF_UPDATE=1` leave the updater off; `ntfy-mac doctor` shows which.
