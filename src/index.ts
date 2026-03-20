import { CONFIG_PATH, loadConfig } from "./config"
import { isSeen, loadState, markSeen, saveState } from "./dedup"
import { discoverTopics, startListener, type MissedMessageResult } from "./ntfy"
import {
  sendConnectionFailureNotification,
  sendNotification,
  sendSetupNotification,
  sendSummaryNotification,
  sendUpdateAvailableNotification,
  sendUpdateSuccessNotification,
} from "./notify"
import { runSetup, runSetupNonInteractive } from "./setup"
import type { NtfyMessage } from "./types"
import {
  detectInstallMethod,
  isNewerVersion,
  performAutoUpdate,
  runManualUpdate,
  takePendingUpdateNotification,
} from "./updater"

// Injected at compile time via `bun build --define APP_VERSION='"x.y.z"'`
// Declared as string | undefined so the typeof guard works at runtime in dev mode.
declare const APP_VERSION: string | undefined
const VERSION: string = typeof APP_VERSION !== "undefined" ? APP_VERSION : "0.0.0"

const UPDATE_CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000

// ─── Update check ─────────────────────────────────────────────────────────────

async function checkForUpdate(): Promise<void> {
  const state = await loadState()
  const lastCheck = state.lastUpdateCheck ?? 0
  if (Date.now() - lastCheck < UPDATE_CHECK_INTERVAL_MS) return

  const res = await fetch("https://api.github.com/repos/jkrumm/ntfy-mac/releases/latest", {
    headers: { "User-Agent": "ntfy-mac" },
  })
  if (!res.ok) return

  const body = (await res.json()) as { tag_name?: string }
  const latest = body.tag_name
  if (!latest) return

  // Re-read state immediately before writing to avoid clobbering concurrent listener writes.
  await saveState({ ...(await loadState()), lastUpdateCheck: Date.now() })

  if (!isNewerVersion(latest, VERSION)) return

  const method = detectInstallMethod()
  if (method === "brew") {
    await sendUpdateAvailableNotification(
      latest,
      "brew upgrade jkrumm/tap/ntfy-mac && brew services restart ntfy-mac",
    )
  } else if (method === "curl") {
    // curl install: auto-update — downloads, replaces binary, exits (launchd restarts)
    await performAutoUpdate(latest)
  }
  // dev: skip silently — running from source, not a compiled release
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
  ntfy-mac update                   Update to the latest version (curl installs)
  ntfy-mac uninstall                Remove all ntfy-mac files and credentials
  ntfy-mac logs                     Tail the daemon log (stdout)
  ntfy-mac logs --error             Tail the error log (stderr)
  ntfy-mac --version                Print version
  ntfy-mac --help                   Print this help

Environment variables (alternative to config file):
  NTFY_URL      ntfy server URL
  NTFY_TOKEN    Access token
  NTFY_TOPICS   Comma-separated topic list (overrides auto-discovery)
`)
  process.exit(0)
}

if (command === "logs") {
  const errorMode = process.argv[3] === "--error"
  const installMethod = detectInstallMethod()
  let logFile: string
  if (installMethod === "brew") {
    let prefix = "/opt/homebrew" // Apple Silicon default
    try {
      prefix = (await Bun.$`brew --prefix`.text()).trim()
    } catch {
      // brew not in PATH or not installed — fall back to default
    }
    logFile = errorMode ? `${prefix}/var/log/ntfy-mac-error.log` : `${prefix}/var/log/ntfy-mac.log`
  } else {
    const { homedir } = await import("os")
    const stateDir = `${homedir()}/.local/share/ntfy-mac`
    logFile = errorMode ? `${stateDir}/ntfy-mac-error.log` : `${stateDir}/ntfy-mac.log`
  }
  console.log(`→ ${logFile}\n`)
  try {
    await Bun.$`tail -f ${logFile}`
  } catch {
    console.error(`Log file not found: ${logFile}`)
    const startCmd =
      installMethod === "brew"
        ? "brew services start ntfy-mac"
        : "launchctl load -w ~/Library/LaunchAgents/com.jkrumm.ntfy-mac.plist"
    console.error(`Is the daemon running? Start it with: ${startCmd}`)
    process.exit(1)
  }
}

if (command === "update") {
  const updateMethod = detectInstallMethod()
  if (updateMethod === "brew") {
    console.log("Managed by Homebrew — run:")
    console.log("  brew upgrade jkrumm/tap/ntfy-mac && brew services restart ntfy-mac")
    process.exit(0)
  }
  if (updateMethod === "dev") {
    console.log("Running in dev mode — updates are not supported")
    process.exit(0)
  }

  process.stdout.write("Checking for updates... ")
  const res = await fetch("https://api.github.com/repos/jkrumm/ntfy-mac/releases/latest", {
    headers: { "User-Agent": "ntfy-mac" },
  })
  if (!res.ok) {
    console.error(`\nFailed to fetch latest version (${res.status})`)
    process.exit(1)
  }
  const body = (await res.json()) as { tag_name?: string }
  const latest = body.tag_name
  if (!latest) {
    console.error("\nFailed to parse latest version")
    process.exit(1)
  }
  if (!isNewerVersion(latest, VERSION)) {
    console.log(`already up to date (${VERSION})`)
    process.exit(0)
  }
  console.log(`${latest} available`)
  process.stdout.write("Downloading and installing... ")
  try {
    await runManualUpdate(latest) // replaces binary, kicks daemon, exits
  } catch (err) {
    console.error(`\nUpdate failed: ${err instanceof Error ? err.message : String(err)}`)
    process.exit(1)
  }
}

if (command === "uninstall") {
  const { homedir } = await import("os")
  const method = detectInstallMethod()
  const plistPath = `${homedir()}/Library/LaunchAgents/com.jkrumm.ntfy-mac.plist`
  const stateDir = `${homedir()}/.local/share/ntfy-mac`
  const binaryPath = `${homedir()}/.local/bin/ntfy-mac`

  console.log("")
  console.log("ntfy-mac uninstall")
  console.log("═".repeat(40))

  if (method === "brew") {
    console.log("Managed by Homebrew — run:")
    console.log("  brew uninstall ntfy-mac")
    console.log("")
    console.log("Then clean up remaining files:")
    console.log(`  rm -rf ${stateDir}`)
    console.log(`  rm -f ${CONFIG_PATH}`)
    process.exit(0)
  }

  if (method === "dev") {
    console.log("Running in dev mode — uninstall is not supported.")
    console.log("To uninstall a curl installation, run the compiled binary directly.")
    process.exit(0)
  }

  // curl install: perform full uninstall
  let errors = 0

  // 1. Stop and unload LaunchAgent
  process.stdout.write("Stopping daemon... ")
  try {
    await Bun.$`launchctl unload -w ${plistPath}`.quiet()
    console.log("✓")
  } catch {
    console.log("(not running)")
  }

  // 2. Remove plist
  process.stdout.write("Removing LaunchAgent... ")
  try {
    await Bun.$`rm -f ${plistPath}`.quiet()
    console.log("✓")
  } catch (err) {
    console.log("✗")
    console.error(`  ${err instanceof Error ? err.message : String(err)}`)
    errors++
  }

  // 3. Delete config file
  process.stdout.write("Removing credentials... ")
  try {
    await Bun.$`rm -f ${CONFIG_PATH}`.quiet()
    console.log("✓")
  } catch {
    console.log("(none found)")
  }

  // 4. Remove state directory (logs, state.json)
  process.stdout.write("Removing state and logs... ")
  try {
    await Bun.$`rm -rf ${stateDir}`.quiet()
    console.log("✓")
  } catch (err) {
    console.log("✗")
    console.error(`  ${err instanceof Error ? err.message : String(err)}`)
    errors++
  }

  // 5. Remove binary (last — so we can still run to this point)
  process.stdout.write("Removing binary... ")
  try {
    await Bun.$`rm -f ${binaryPath}`.quiet()
    console.log("✓")
  } catch (err) {
    console.log("✗")
    console.error(`  ${err instanceof Error ? err.message : String(err)}`)
    errors++
  }

  console.log("")
  if (errors === 0) {
    console.log("ntfy-mac has been uninstalled.")
  } else {
    console.log(`Uninstall completed with ${errors} error(s). Some files may need manual cleanup.`)
    process.exit(1)
  }
  process.exit(0)
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

// Send success notification if a previous auto-update wrote a pending version
takePendingUpdateNotification()
  .then((version) => {
    if (version) return sendUpdateSuccessNotification(version)
  })
  .catch(() => {})

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
