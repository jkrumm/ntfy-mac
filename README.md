# ntfy-mac

Forward [ntfy](https://ntfy.sh) notifications to macOS Notification Center.

Runs as a background daemon via `brew services`. Streams messages over SSE, stores credentials in macOS Keychain, and handles missed messages gracefully after reconnects.

> **Status:** Under active development — see [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the roadmap.

## Install

```bash
brew install jkrumm/ntfy-mac/ntfy-mac
ntfy-mac setup
brew services start ntfy-mac
```

## License

MIT
