import { loadConfig } from "./config"
import { isSeen, loadState, markSeen, saveState } from "./dedup"
import { discoverTopics, startListener, type MissedMessageResult } from "./ntfy"
import {
  sendConnectionFailureNotification,
  sendNotification,
  sendSetupNotification,
  sendSummaryNotification,
  sendUpdateNotification,
} from "./notify"
import { runSetup, runSetupNonInteractive } from "./setup"
import type { NtfyMessage } from "./types"

// Injected at compile time via `bun build --define APP_VERSION='"x.y.z"'`
// Declared as string | undefined so the typeof guard works at runtime in dev mode.
declare const APP_VERSION: string | undefined
const VERSION: string = typeof APP_VERSION !== "undefined" ? APP_VERSION : "0.0.0"

const UPDATE_CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000

// ─── Update check ─────────────────────────────────────────────────────────────

function isNewerVersion(latest: string, current: string): boolean {
  const parse = (v: string) => v.replace(/^v/, "").split(".").map(Number)
  const [la, lb, lc] = parse(latest)
  const [ca, cb, cc] = parse(current)
  if (la !== ca) return la > ca
  if (lb !== cb) return lb > cb
  return lc > cc
}

async function checkForUpdate(): Promise<void> {
  const state = await loadState()
  const lastCheck = state.lastUpdateCheck ?? 0
  if (Date.now() - lastCheck < UPDATE_CHECK_INTERVAL_MS) return

  const res = await fetch("https://api.github.com/repos/jkrumm/homebrew-ntfy-mac/releases/latest", {
    headers: { "User-Agent": "ntfy-mac" },
  })
  if (!res.ok) return

  const body = (await res.json()) as { tag_name?: string }
  const latest = body.tag_name
  if (!latest) return

  await saveState({ ...state, lastUpdateCheck: Date.now() })

  if (isNewerVersion(latest, VERSION)) {
    await sendUpdateNotification(latest)
  }
}

// ─── Message handler ──────────────────────────────────────────────────────────

async function handleMessage(msg: NtfyMessage): Promise<void> {
  const state = await loadState()
  if (isSeen(state, msg.id)) return
  await sendNotification(msg)
  await saveState(markSeen(state, msg.id))
}

async function handleMissed(result: MissedMessageResult): Promise<void> {
  if (result.type === "individual") {
    for (const msg of result.messages) await handleMessage(msg)
  } else if (result.type === "summary") {
    await sendSummaryNotification(result.count, result.oldestTopic)
  }
  // silent → do nothing
}

// ─── Entry point ──────────────────────────────────────────────────────────────

const command = process.argv[2]

if (command === "--version" || command === "-v") {
  console.log(`ntfy-mac ${VERSION}`)
  process.exit(0)
}

if (command === "--help" || command === "-h") {
  console.log(`ntfy-mac ${VERSION}

Forward ntfy notifications to macOS Notification Center.

Usage:
  ntfy-mac                          Start the daemon (default)
  ntfy-mac setup                    Interactive setup wizard
  ntfy-mac setup --url <url>        Non-interactive setup
               --token <token>
  ntfy-mac logs                     Tail the daemon log (stdout)
  ntfy-mac logs --error             Tail the error log (stderr)
  ntfy-mac --version                Print version
  ntfy-mac --help                   Print this help

Environment variables (alternative to Keychain):
  NTFY_URL      ntfy server URL
  NTFY_TOKEN    Access token
  NTFY_TOPICS   Comma-separated topic list (overrides auto-discovery)
`)
  process.exit(0)
}

if (command === "logs") {
  const errorMode = process.argv[3] === "--error"
  let prefix = "/opt/homebrew" // Apple Silicon default
  try {
    prefix = (await Bun.$`brew --prefix`.text()).trim()
  } catch {
    // brew not in PATH or not installed — fall back to default
  }
  const logFile = errorMode
    ? `${prefix}/var/log/ntfy-mac-error.log`
    : `${prefix}/var/log/ntfy-mac.log`
  console.log(`→ ${logFile}\n`)
  try {
    await Bun.$`tail -f ${logFile}`
  } catch {
    console.error(`Log file not found: ${logFile}`)
    console.error("Is the daemon running? Start it with: brew services start ntfy-mac")
    process.exit(1)
  }
}

if (command === "setup") {
  // Non-interactive mode: ntfy-mac setup --url <url> --token <token>
  const args = process.argv.slice(3)
  const urlIdx = args.indexOf("--url")
  const tokenIdx = args.indexOf("--token")
  const hasAnyFlag = urlIdx !== -1 || tokenIdx !== -1
  if (hasAnyFlag) {
    // Partial flags → error instead of silently falling back to interactive
    if (urlIdx === -1 || tokenIdx === -1) {
      console.error("Error: --url and --token must both be provided")
      console.error("Usage: ntfy-mac setup --url <url> --token <token>")
      process.exit(1)
    }
    const url = args[urlIdx + 1]
    const token = args[tokenIdx + 1]
    if (!url || !token) {
      console.error("Error: --url and --token require values")
      process.exit(1)
    }
    await runSetupNonInteractive(url, token)
  } else {
    await runSetup()
  }
  process.exit(0)
}

const config = await loadConfig()
if (!config) {
  await sendSetupNotification()
  console.error("ntfy-mac is not configured. Run: ntfy-mac setup")
  process.exit(1)
}

// Non-blocking update check — never throws
checkForUpdate().catch(() => {})

let topics: string[]
try {
  topics = config.topics ?? (await discoverTopics(config))
} catch (err) {
  const message = err instanceof Error ? err.message : String(err)
  console.error(`ntfy-mac: failed to discover topics — ${message}`)
  console.error("Check your connection and credentials, then restart.")
  process.exit(1)
}
if (topics.length === 0) {
  console.error("No subscribed topics found. Subscribe to topics in ntfy first.")
  process.exit(1)
}

console.log(`ntfy-mac ${VERSION} — listening on: ${topics.join(", ")}`)

await startListener(config, topics, handleMessage, handleMissed, sendConnectionFailureNotification)
