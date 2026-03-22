# Contributing

## Prerequisites

- [Bun](https://bun.sh) (`brew install bun`)
- macOS (required for UserNotifications and the Swift helper)

## Setup

```bash
git clone https://github.com/jkrumm/ntfy-mac.git
cd ntfy-mac
bun install
```

## Development

```bash
bun src/index.ts setup     # Configure credentials interactively
bun src/index.ts           # Run the daemon (Ctrl+C to stop)
NTFY_DEBUG=1 bun src/index.ts  # Verbose mode: keepalives, message IDs, poll calls
bun test                   # Run unit tests
bun run validate           # Format + typecheck + lint + test
```

### Swift notification helper

The notification system uses a Swift `.app` bundle (`assets/ntfy-notify.app`) that communicates with the TypeScript daemon via JSON on stdin. To build it:

```bash
bun run build:helper       # Compiles ntfy-notify.swift → assets/ntfy-notify.app
```

For development, copy the built helper to `~/Applications/` so Launch Services registers the icon:

```bash
cp -R assets/ntfy-notify.app ~/Applications/
```

## Building

```bash
bun run build    # Produces dist/ntfy-mac (arm64) + dist/ntfy-notify.app.tar.gz
```

Binaries are fully self-contained — no Bun runtime needed on the target machine.

## Project structure

```
src/
  index.ts          Entry point — CLI routing and daemon startup
  ntfy.ts           SSE connection, polling, topic discovery
  notify.ts         Message → notification payload mapping
  notifications.ts  Swift helper communication (NotificationBuilder)
  config.ts         Config file loading and persistence
  config-cli.ts     `ntfy-mac config` subcommands
  setup.ts          Interactive and non-interactive setup wizard
  doctor.ts         `ntfy-mac doctor` health checks
  dedup.ts          Message deduplication and state persistence
  updater.ts        Version checking and auto-update
  pidlock.ts        Single-instance enforcement
  types.ts          Shared type definitions
  emojis.ts         Tag → emoji mapping (generated)
```

## Release process

Releases are triggered manually via the **Run workflow** button in the Actions tab:

1. Go to Actions → Release → Run workflow, optionally choose a release type
2. Commit messages following [Conventional Commits](https://www.conventionalcommits.org) determine the version bump (or the chosen type overrides it)
3. A GitHub Release is created with the changelog
4. arm64 binary and Swift helper are compiled and attached
5. `Formula/ntfy-mac.rb` in `jkrumm/homebrew-tap` is updated automatically with new version and SHA-256 checksums
