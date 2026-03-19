# ntfy-mac — Implementation Plan

Forward ntfy notifications to macOS Notification Center via a native daemon.

## Architecture Decisions

### Why Bun + TypeScript (not Go/Swift)
- `bun build --compile` produces a fully self-contained binary — no runtime, no dependencies
- Cross-compilation to both `darwin-arm64` and `darwin-x64` in CI
- TypeScript is the fastest iteration path for a solo project
- Bun's native Keychain API (`Bun.secrets`) replaces manual `security` CLI calls

### Why a Homebrew tap (not homebrew-core yet)
- homebrew-core requires ≥75 GitHub stars + `brew audit --strict` compliance
- Tap is immediately installable without any ceremony: `brew install jkrumm/ntfy-mac/ntfy-mac`
- Naming `homebrew-ntfy-mac` makes Homebrew auto-resolve tap as `jkrumm/ntfy-mac`

### Why osascript (not native macOS API)
- No Xcode required, no Swift/ObjC, no app bundle
- Supports all 4 notification fields: title, subtitle, message, sound
- Works reliably from a binary without code signing (for now)
- Limitation: no custom icon, no click callbacks — acceptable tradeoff

### Credential storage
- macOS Keychain via `Bun.secrets` (native, no plaintext files)
- Keys: `ntfy-mac:url`, `ntfy-mac:token`
- Fallback: `NTFY_URL` / `NTFY_TOKEN` env vars (for CI/server use)

### Connection strategy
- Primary: SSE (`GET /sse?topics=...&since=<lastId|latest>`)
- Fallback: JSON polling (`GET /json?since=<lastId>&poll=1`) during backoff
- Backoff: 5s → 10s → 20s → ... → 5min cap

### State file
- `~/.local/share/ntfy-mac/state.json`
- Fields: `seen` (Record<id, timestamp>), `lastMessageId`, `lastUpdateCheck`
- Cleanup on load: drop entries >48h, trim to 1000 most recent

---

## Prerequisites

Before implementing, ensure you have:
- Bun installed (`brew install bun`)
- `gh` CLI authenticated (`gh auth status`)
- `semantic-release` compatible npm token (for auto-publishing GitHub Releases)
- Repository created at `github.com/jkrumm/homebrew-ntfy-mac`

---

## Step-by-Step Implementation

### Step 1 — Project Scaffold

Files to create:
- `package.json` — scripts, dependencies, semantic-release config
- `tsconfig.json` — strict TypeScript, Bun types
- `.prettierrc` — formatting config
- `.oxlintrc.json` — linting rules
- `.gitignore` — node_modules, dist, state files
- `README.md` — minimal placeholder (full docs in Step 11)

**package.json scripts:**
```json
{
  "scripts": {
    "start": "bun src/index.ts",
    "setup": "bun src/index.ts setup",
    "build:arm64": "bun build --compile --target=bun-darwin-arm64 src/index.ts --outfile dist/ntfy-mac-arm64",
    "build:x64": "bun build --compile --target=bun-darwin-x64 src/index.ts --outfile dist/ntfy-mac-x64",
    "build": "bun run build:arm64 && bun run build:x64",
    "test": "bun test",
    "lint": "bunx oxlint src",
    "format": "bunx prettier --write .",
    "format:check": "bunx prettier --check .",
    "validate": "bun run format:check && bun run lint && bun run test"
  },
  "devDependencies": {
    "@types/bun": "latest",
    "prettier": "latest",
    "oxlint": "latest",
    "semantic-release": "latest",
    "@semantic-release/changelog": "latest",
    "@semantic-release/git": "latest",
    "@semantic-release/github": "latest"
  }
}
```

**semantic-release config in package.json:**
```json
{
  "release": {
    "branches": ["main"],
    "plugins": [
      "@semantic-release/commit-analyzer",
      "@semantic-release/release-notes-generator",
      ["@semantic-release/changelog", { "changelogFile": "CHANGELOG.md" }],
      "@semantic-release/github",
      ["@semantic-release/git", {
        "assets": ["CHANGELOG.md"],
        "message": "chore(release): ${nextRelease.version}"
      }]
    ]
  }
}
```

**tsconfig.json:**
```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "types": ["bun-types"]
  },
  "include": ["src", "tests"]
}
```

---

### Step 2 — `src/types.ts` + `src/config.ts`

**`types.ts`** — all shared interfaces:
```ts
export interface NtfyMessage {
  id: string
  time: number
  topic: string
  title?: string
  message: string
  priority?: 1 | 2 | 3 | 4 | 5
  tags?: string[]
  click?: string
}

export interface Config {
  url: string          // e.g. https://ntfy.jkrumm.com
  token: string
  topics?: string[]    // override auto-discovery
}

export interface AppState {
  seen: Record<string, number>   // id → unix timestamp (ms)
  lastMessageId: string | null
  lastUpdateCheck: number | null // unix timestamp (ms)
}
```

**`config.ts`** — load credentials:
1. Try `Bun.secrets.get("ntfy-mac:url")` + `Bun.secrets.get("ntfy-mac:token")`
2. Fall back to `process.env.NTFY_URL` + `process.env.NTFY_TOKEN`
3. If `NTFY_TOPICS` env var set → parse as comma-separated list
4. If no config found → return `null` (caller handles setup notification)

Validation: URL must be valid HTTP/HTTPS. Token must be non-empty.

---

### Step 3 — `src/dedup.ts`

State file location: `~/.local/share/ntfy-mac/state.json`

Functions:
- `loadState(): AppState` — read file, parse JSON, run cleanup
- `saveState(state: AppState): void` — atomic write (write to `.tmp`, rename)
- `cleanup(state: AppState): AppState` — drop seen entries >48h, trim to 1000
- `isSeen(state: AppState, id: string): boolean`
- `markSeen(state: AppState, id: string): AppState`

Atomic write pattern (prevents corrupt state on crash):
```ts
const tmp = stateFile + ".tmp"
await Bun.write(tmp, JSON.stringify(state, null, 2))
await Bun.$`mv ${tmp} ${stateFile}`
```

---

### Step 4 — `src/ntfy.ts`

**Topic discovery:**
```ts
async function discoverTopics(config: Config): Promise<string[]>
// GET /v1/account → body.subscriptions[].topic
// Throws on auth failure (401) or network error
```

**SSE streaming:**
```ts
async function connectSSE(
  config: Config,
  topics: string[],
  since: string,           // message ID or "latest"
  onMessage: (msg: NtfyMessage) => void,
  onError: (err: Error) => void
): Promise<void>
// URL: {url}/sse?topics={topics.join(",")}&since={since}
// Headers: Authorization: Bearer {token}
// Parse text/event-stream: data: {...}\n\n lines
// Call onMessage for each valid NtfyMessage
// Call onError on connection drop
```

**Polling fallback:**
```ts
async function pollMessages(
  config: Config,
  topics: string[],
  since: string
): Promise<NtfyMessage[]>
// GET /json?topics=...&since=...&poll=1
// Parse newline-delimited JSON (one message per line)
```

**Connection loop** (exported main function):
```ts
async function startListener(
  config: Config,
  onMessage: (msg: NtfyMessage) => void
): Promise<never>
```
- Load `lastMessageId` from state
- Start SSE with `since = lastMessageId ?? "latest"`
- On SSE error: poll once, then wait with exponential backoff (5s→5min)
- Update `lastMessageId` in state after each message

---

### Step 5 — `src/notify.ts`

**Priority → sound mapping:**
```ts
const SOUND: Record<number, string | null> = {
  5: "Sosumi",
  4: "Ping",
  3: "Pop",
  2: null,
  1: null,
}
```

**Tag → emoji rendering:**
Ntfy tags map to emoji: `+1` → `👍`, `warning` → `⚠️`, `rotating_light` → `🚨`, etc.
Use a lookup table for common ones; pass unknown tags as-is.

**`sendNotification(msg: NtfyMessage): Promise<void>`:**
```ts
// Build osascript args:
// title: msg.title ?? capitalize(msg.topic)
// subtitle: msg.topic + " • " + emojiTags (if any)
// message: msg.message
// sound name: SOUND[msg.priority ?? 3] ?? undefined

const script = buildOsaScript({ title, subtitle, body, sound })
await Bun.$`osascript -e ${script}`

// If msg.click: await Bun.$`open ${msg.click}`
```

**`sendSummaryNotification(count: number, oldestTopic: string): Promise<void>`:**
```ts
// title: "ntfy-mac"
// message: `${count} notifications while you were away`
// subtitle: "Open ntfy to review"
// sound: "Pop"
```

**`sendSetupNotification(): Promise<void>`:**
```ts
// title: "ntfy-mac setup required"
// message: "Run: ntfy-mac setup"
// sound: "Ping"
```

**`sendUpdateNotification(version: string): Promise<void>`:**
```ts
// title: "ntfy-mac update available"
// message: `brew upgrade jkrumm/ntfy-mac/ntfy-mac && brew services restart ntfy-mac`
```

---

### Step 6 — `src/setup.ts`

Interactive CLI wizard triggered by `ntfy-mac setup`.

Uses `prompt()` (Bun built-in) for user input.

Flow:
1. Print welcome header
2. Prompt: "NTFY server URL" (default: `https://ntfy.example.com`)
3. Prompt: "Auth token" (mask input if possible)
4. Test connection: `GET /v1/account` with provided credentials
5. On success: show found topics, save to Keychain via `Bun.secrets.set`
6. On failure: print error, offer retry
7. Print next steps: `brew services start ntfy-mac`

Keychain keys:
```ts
await Bun.secrets.set("ntfy-mac:url", url)
await Bun.secrets.set("ntfy-mac:token", token)
```

---

### Step 7 — `src/index.ts`

Entry point and orchestration:

```ts
// Subcommand dispatch
const command = process.argv[2]
if (command === "setup") {
  await runSetup()
  process.exit(0)
}

// Load config
const config = await loadConfig()
if (!config) {
  await sendSetupNotification()
  process.exit(1)
}

// Check for updates (non-blocking, max once per 24h)
checkForUpdate(config).catch(() => {}) // never throws

// Discover topics
const topics = config.topics ?? await discoverTopics(config)
if (topics.length === 0) {
  console.error("No topics found. Subscribe to topics in ntfy first.")
  process.exit(1)
}

// Start listener loop (never returns)
await startListener(config, async (msg) => {
  const state = loadState()
  if (isSeen(state, msg.id)) return
  await sendNotification(msg)
  saveState(markSeen(state, msg.id))
})
```

**Update check logic:**
```ts
async function checkForUpdate(config: Config): Promise<void>
// GET https://api.github.com/repos/jkrumm/homebrew-ntfy-mac/releases/latest
// Parse tag_name (e.g. "v1.2.0"), compare to VERSION constant (injected at build)
// If newer AND state.lastUpdateCheck < Date.now() - 24h:
//   sendUpdateNotification(latestVersion)
//   saveState({ ...state, lastUpdateCheck: Date.now() })
```

**VERSION constant** — injected at build time via `--define`:
```ts
declare const APP_VERSION: string // set in bun build --define
```

Build scripts add: `--define APP_VERSION='"1.0.0"'` (semantic-release updates this).

---

### Step 8 — Tests

**`tests/dedup.test.ts`:**
- `isSeen` returns false for new ID, true after `markSeen`
- `cleanup` drops entries older than 48h
- `cleanup` trims to 1000 most recent when over limit
- `lastMessageId` persists across save/load cycle
- Atomic write: `.tmp` file cleaned up after successful save

**`tests/notify.test.ts`:**
- Priority 5 → sound "Sosumi"
- Priority 3 → sound "Pop"
- Priority 1 → no sound (null)
- Title falls back to capitalized topic when `msg.title` is undefined
- Tags with known emoji → rendered correctly in subtitle
- Unknown tags → passed through as-is

**`tests/ntfy.test.ts`:**
- `NtfyMessage` JSON parsing: all fields, optional fields
- Invalid JSON line → skipped (no throw)
- Missed-message categorization:
  - 3 messages, 30min old → returns `{ type: "individual", messages }`
  - 8 messages, 3h old → returns `{ type: "summary", count: 8 }`
  - 5 messages, 15h old → returns `{ type: "silent" }`

---

### Step 9 — GitHub Actions Release Workflow

File: `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: macos-latest  # required for darwin cross-compile targets
    permissions:
      contents: write
      issues: write
      pull-requests: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # semantic-release needs full history

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - run: bun install --frozen-lockfile

      - name: Validate
        run: bun run validate

      - name: Build binaries
        run: bun run build

      - name: Release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: bunx semantic-release

  update-formula:
    needs: release
    runs-on: ubuntu-latest
    if: ${{ needs.release.outputs.new_release_published == 'true' }}

    steps:
      - uses: actions/checkout@v4

      - name: Download release assets
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          VERSION: ${{ needs.release.outputs.new_release_version }}
        run: |
          gh release download "v${VERSION}" --pattern "ntfy-mac-*" --dir dist/

      - name: Compute checksums
        run: |
          echo "SHA256_ARM64=$(sha256sum dist/ntfy-mac-arm64 | cut -d' ' -f1)" >> $GITHUB_ENV
          echo "SHA256_X64=$(sha256sum dist/ntfy-mac-x64 | cut -d' ' -f1)" >> $GITHUB_ENV

      - name: Update formula
        env:
          VERSION: ${{ needs.release.outputs.new_release_version }}
        run: |
          sed -i "s/version \".*\"/version \"${VERSION}\"/" Formula/ntfy-mac.rb
          sed -i "s/sha256 \".*\" # arm64/sha256 \"${SHA256_ARM64}\" # arm64/" Formula/ntfy-mac.rb
          sed -i "s/sha256 \".*\" # x64/sha256 \"${SHA256_X64}\" # x64/" Formula/ntfy-mac.rb

      - name: Commit formula update
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Formula/ntfy-mac.rb
          git commit -m "chore(formula): update to v${VERSION}"
          git push
```

**Note:** semantic-release must output `new_release_published` and `new_release_version` as job outputs. Use `@semantic-release/github` plugin which sets these outputs automatically.

---

### Step 10 — `Formula/ntfy-mac.rb`

```ruby
class NtfyMac < Formula
  desc "Forward ntfy notifications to macOS Notification Center"
  homepage "https://github.com/jkrumm/homebrew-ntfy-mac"
  version "0.0.0"  # updated by CI on each release
  license "MIT"

  on_arm do
    url "https://github.com/jkrumm/homebrew-ntfy-mac/releases/download/v#{version}/ntfy-mac-arm64"
    sha256 "0000000000000000000000000000000000000000000000000000000000000000" # arm64
  end

  on_intel do
    url "https://github.com/jkrumm/homebrew-ntfy-mac/releases/download/v#{version}/ntfy-mac-x64"
    sha256 "0000000000000000000000000000000000000000000000000000000000000000" # x64
  end

  def install
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    bin.install "ntfy-mac-#{arch}" => "ntfy-mac"
  end

  service do
    run [opt_bin/"ntfy-mac"]
    keep_alive true
    log_path "#{Dir.home}/Library/Logs/ntfy-mac.log"
    error_log_path "#{Dir.home}/Library/Logs/ntfy-mac.error.log"
  end

  test do
    system "#{bin}/ntfy-mac", "--version"
  end
end
```

---

### Step 11 — `README.md`

Full user-facing documentation covering:
- What it does (1 paragraph)
- Install + configure + start (3 commands)
- How it works (SSE streaming, Keychain storage, missed-message handling)
- Upgrade instructions
- Uninstall instructions
- Configuration reference (env var overrides)
- Troubleshooting (logs location, common errors)
- Contributing guide (dev setup, running tests, building)
- License

---

## Testing Checklist

After full implementation, verify:

- [ ] `bun test` — all unit tests pass
- [ ] `bun run validate` — format + lint + test all pass
- [ ] `bun run build` — produces `dist/ntfy-mac-arm64` and `dist/ntfy-mac-x64`
- [ ] Binary runs: `./dist/ntfy-mac-arm64 --version` (or equivalent)
- [ ] `brew install jkrumm/ntfy-mac/ntfy-mac` succeeds
- [ ] `ntfy-mac setup` wizard runs, saves to Keychain, shows success
- [ ] No config → macOS "setup required" notification appears
- [ ] `brew services start ntfy-mac` starts LaunchAgent
- [ ] Send ntfy test message → notification appears with correct sound
- [ ] Priority 5 message → "Sosumi" sound
- [ ] Priority 3 message → "Pop" sound
- [ ] Low-priority message → no sound
- [ ] Message with `click` URL → browser opens
- [ ] Stop service 2h, restart → recent messages shown individually
- [ ] Stop service 8h, restart → single summary notification
- [ ] Stop service 15h, restart → silent (no notification storm)
- [ ] Restart immediately → no duplicate notifications (dedup working)
- [ ] Push feat commit to `main` → CI creates release, formula auto-updates

---

## Release Checklist

Before first release:
- [ ] GitHub repo created: `jkrumm/homebrew-ntfy-mac`
- [ ] `GITHUB_TOKEN` permissions: `contents: write`, `issues: write`, `pull-requests: write`
- [ ] semantic-release dry run passes locally
- [ ] Initial formula sha256 placeholders noted in `Formula/ntfy-mac.rb`
- [ ] README complete and accurate
- [ ] `brew audit Formula/ntfy-mac.rb` passes (no errors)
- [ ] Tag `v1.0.0` triggers full release pipeline

---

## File Creation Order (for iterative implementation)

1. `package.json`, `tsconfig.json`, `.prettierrc`, `.oxlintrc.json`, `.gitignore`
2. `src/types.ts`, `src/config.ts`
3. `src/dedup.ts` + `tests/dedup.test.ts`
4. `src/ntfy.ts` + `tests/ntfy.test.ts`
5. `src/notify.ts` + `tests/notify.test.ts`
6. `src/setup.ts`
7. `src/index.ts`
8. `.github/workflows/release.yml`
9. `Formula/ntfy-mac.rb`
10. `README.md` (full version)
