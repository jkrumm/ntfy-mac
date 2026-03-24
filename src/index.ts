import { CONFIG_PATH, loadConfig, loadStoredConfig } from "./config"
import { isSeen, markSeen } from "./dedup"
import { loadState, saveState, StateManager } from "./state"
import {
  NotificationBuilder,
  sendNotificationPayload,
  sendNotificationNonBlocking,
} from "./notifications"
import { discoverTopics, startListener, type MissedMessageResult } from "./ntfy"
import {
  buildNtfyPayload,
  DEFAULT_ACTIONS,
  DEFAULT_CATEGORY_ID,
  renderTags,
  resolvePriorityConfig,
  sendConnectionFailureNotification,
  sendSetupNotification,
  sendSummaryNotification,
  sendUpdateAvailableNotification,
  sendUpdateSuccessNotification,
} from "./notify"
import { NotificationQueue } from "./queue"
import { handleConfigCommand } from "./config-cli"
import { startReminderPoll } from "./reminders"
import { runDoctor } from "./doctor"
import { acquirePidLock, releasePidLock } from "./pidlock"
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

async function checkForUpdate(stateManager: StateManager): Promise<void> {
  const lastCheck = stateManager.get().lastUpdateCheck ?? 0
  if (Date.now() - lastCheck < UPDATE_CHECK_INTERVAL_MS) return

  const res = await fetch("https://api.github.com/repos/jkrumm/ntfy-mac/releases/latest", {
    headers: { "User-Agent": "ntfy-mac" },
  })
  if (!res.ok) return

  const body = (await res.json()) as { tag_name?: string }
  const latest = body.tag_name
  if (!latest) return

  stateManager.update((s) => ({ ...s, lastUpdateCheck: Date.now() }))

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

// ─── Entry point ──────────────────────────────────────────────────────────────

const command = process.argv[2]

if (command === "version" || command === "--version" || command === "-v") {
  console.log(`ntfy-mac ${VERSION}`)
  process.exit(0)
}

function printHelp(): void {
  console.log(`ntfy-mac ${VERSION}

Forward ntfy notifications to macOS Notification Center.

Usage:
  ntfy-mac                          Show this help
  ntfy-mac setup                    Interactive setup wizard
  ntfy-mac setup --url <url>        Non-interactive setup
               --token <token>
  ntfy-mac doctor                   Check health and configuration
  ntfy-mac doctor --json            Machine-readable health report
  ntfy-mac subscribe                Show subscribed topics
  ntfy-mac subscribe <topic>        Add a topic (merged with auto-discovered)
  ntfy-mac unsubscribe <topic>      Remove a locally added topic
  ntfy-mac config                   Manage configuration
  ntfy-mac config sounds            Show/change notification sounds
  ntfy-mac config dismiss           Show/change auto-dismiss timing
  ntfy-mac notify -m "message"      Send a local notification
  ntfy-mac sounds                   Preview all macOS notification sounds
  ntfy-mac sounds <filter>          Preview sounds matching a name (e.g. "ping")
  ntfy-mac logs                     Tail the daemon log (stdout)
  ntfy-mac logs --error             Tail the error log (stderr)
  ntfy-mac update                   Update to the latest version
  ntfy-mac uninstall                Remove all ntfy-mac files and credentials
  ntfy-mac version                  Print version
  ntfy-mac help                     Print this help

Notify (local notification, no server required):
  ntfy-mac notify -m "text"                        Simple notification
  ntfy-mac notify -t "Title" -m "text"              With title
  ntfy-mac notify -t "Title" -m "text" -p 5         Priority 1-5 (sound/urgency)
  ntfy-mac notify -m "text" --tag warning            With emoji tags (repeatable)
  ntfy-mac notify -m "text" --url https://...       Click to open URL
  ntfy-mac notify -m "text" -d 10                   Auto-dismiss after 10 seconds
  echo '{"title":"T","body":"B"}' | ntfy-mac notify --json   Full payload via stdin

The daemon is managed by launchd (brew services / LaunchAgent).
To start manually: ntfy-mac start
`)
}

if (command === "help" || command === "--help" || command === "-h") {
  printHelp()
  process.exit(0)
}

if (command === "notify") {
  const args = process.argv.slice(3)

  if (args.includes("--json")) {
    // Full payload from stdin
    const input = await Bun.stdin.text()
    if (!input.trim()) {
      console.error("Error: --json requires a JSON payload on stdin")
      process.exit(1)
    }
    try {
      const payload = JSON.parse(input) as import("./notifications").NotificationPayload
      if (!payload.body) {
        console.error('Error: JSON payload requires a "body" field')
        process.exit(1)
      }
      payload.title ??= "ntfy-mac"
      if (!payload.actions || payload.actions.length === 0) {
        payload.actions = DEFAULT_ACTIONS
        payload.categoryId ??= DEFAULT_CATEGORY_ID
      }
      await sendNotificationPayload(payload)
    } catch (err) {
      console.error(`Error: invalid JSON — ${err instanceof Error ? err.message : String(err)}`)
      process.exit(1)
    }
    process.exit(0)
  }

  // Flag-based mode
  function flag(short: string, long: string): string | undefined {
    for (let i = 0; i < args.length; i++) {
      if (args[i] === short || args[i] === long) return args[i + 1]
    }
    return undefined
  }

  function flagAll(long: string): string[] {
    const values: string[] = []
    for (let i = 0; i < args.length; i++) {
      if (args[i] === long && args[i + 1]) values.push(args[i + 1])
    }
    return values
  }

  const message = flag("-m", "--message")
  if (!message) {
    console.error("Error: -m / --message is required")
    console.error(
      'Usage: ntfy-mac notify -m "message" [-t title] [-p 1-5] [--tag name] [--url url]',
    )
    process.exit(1)
  }

  const title = flag("-t", "--title") ?? "ntfy-mac"
  const priorityRaw = flag("-p", "--priority")
  const priority = priorityRaw ? Math.max(1, Math.min(5, parseInt(priorityRaw, 10) || 3)) : 3
  const tags = flagAll("--tag")
  const clickUrl = flag("--url", "--url")
  const dismissAfterRaw = flag("-d", "--dismiss-after")
  let dismissAfter: number | undefined
  if (dismissAfterRaw !== undefined) {
    const parsed = Number(dismissAfterRaw)
    if (!Number.isFinite(parsed) || parsed < 0) {
      console.error("Error: -d / --dismiss-after must be a number >= 0")
      process.exit(1)
    }
    dismissAfter = parsed
  }

  // Load overrides from config (notify command doesn't require full config)
  const notifyConfig = await loadStoredConfig()
  const soundOverrides = (notifyConfig.sounds ?? undefined) as
    | import("./types").SoundConfig
    | undefined
  const dismissOverrides = (notifyConfig.dismiss ?? undefined) as
    | import("./types").DismissConfig
    | undefined

  const {
    sound,
    interruptionLevel,
    relevanceScore,
    dismissAfter: configDismiss,
  } = resolvePriorityConfig(priority, soundOverrides, dismissOverrides)

  // CLI flag overrides config; config overrides default. 0 = never auto-dismiss.
  const effectiveDismiss =
    dismissAfter !== undefined
      ? dismissAfter > 0
        ? dismissAfter
        : undefined
      : configDismiss > 0
        ? configDismiss
        : undefined

  const tagLine = renderTags(tags)

  const builder = new NotificationBuilder(title, message)
    .sound(sound)
    .interruptionLevel(interruptionLevel)
    .relevanceScore(relevanceScore)

  if (tagLine) builder.subtitle(tagLine)
  if (clickUrl) builder.clickUrl(clickUrl)
  if (effectiveDismiss) builder.dismissAfter(effectiveDismiss)
  builder.actions(DEFAULT_ACTIONS, DEFAULT_CATEGORY_ID)

  await builder.send()
  process.exit(0)
}

if (command === "sounds") {
  const ALL_SOUNDS: import("./notifications").SystemSound[] = [
    "Basso",
    "Blow",
    "Bottle",
    "Frog",
    "Funk",
    "Glass",
    "Hero",
    "Morse",
    "Ping",
    "Pop",
    "Purr",
    "Sosumi",
    "Submarine",
    "Tink",
  ]

  const filter = process.argv[3]?.toLowerCase()
  const sounds = filter ? ALL_SOUNDS.filter((s) => s.toLowerCase().includes(filter)) : ALL_SOUNDS

  if (sounds.length === 0) {
    console.error(`No sound matching "${filter}". Available: ${ALL_SOUNDS.join(", ")}`)
    process.exit(1)
  }

  for (const sound of sounds) {
    console.log(`Playing: ${sound}`)
    await new NotificationBuilder("Sound Preview", sound).sound(sound).send()
    await Bun.sleep(2000)
  }
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
    console.log("Upgrading via Homebrew...")
    try {
      await Bun.$`brew upgrade jkrumm/tap/ntfy-mac`
      await Bun.$`brew services restart ntfy-mac`
      console.log("Done.")
    } catch (err) {
      console.error(`Upgrade failed: ${err instanceof Error ? err.message : String(err)}`)
      process.exit(1)
    }
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

if (command === "subscribe" || command === "unsubscribe") {
  const {
    loadConfig: loadCfg,
    loadStoredConfig: loadStored,
    updateStoredConfig: updateStored,
  } = await import("./config")
  const { discoverTopics: discover } = await import("./ntfy")

  const topic = process.argv[3]

  if (command === "subscribe" && topic === "reset") {
    await updateStored({ extraTopics: undefined })
    console.log("Local topic additions cleared. Daemon will use auto-discovery only.")
    console.log("Restart the daemon to apply: brew services restart ntfy-mac")
    process.exit(0)
  }

  if (command === "subscribe" && !topic) {
    // Show current topics
    const cfg = await loadCfg()
    if (!cfg) {
      console.error("Not configured. Run: ntfy-mac setup")
      process.exit(1)
    }
    const stored = await loadStored()
    const extra = (stored.extraTopics as string[]) ?? []

    let discovered: string[] = []
    if (!cfg.topics) {
      try {
        discovered = await discover(cfg)
      } catch (err) {
        console.error(`Could not discover topics: ${err instanceof Error ? err.message : err}`)
      }
    }

    const effective = cfg.topics ?? [...new Set([...discovered, ...extra])]

    console.log("Subscribed topics\n")
    if (cfg.topics) {
      console.log("  Source: NTFY_TOPICS environment variable (full override)")
    } else {
      console.log("  Source: auto-discovery + local additions")
    }
    console.log("")
    for (const t of effective) {
      const isExtra = extra.includes(t) && !discovered.includes(t)
      console.log(`  ${t}${isExtra ? " (local)" : ""}`)
    }
    if (effective.length === 0) console.log("  (none)")
    console.log("")
    console.log("Add a topic:    ntfy-mac subscribe <topic>")
    console.log("Remove a topic: ntfy-mac unsubscribe <topic>")
    console.log("Reset to auto:  ntfy-mac subscribe reset")
    process.exit(0)
  }

  if (!topic) {
    console.error("Usage: ntfy-mac unsubscribe <topic>")
    process.exit(1)
  }

  const stored = await loadStored()
  const extra = (stored.extraTopics as string[]) ?? []

  if (command === "subscribe") {
    if (extra.includes(topic)) {
      console.log(`Topic "${topic}" is already subscribed.`)
      process.exit(0)
    }
    await updateStored({ extraTopics: [...extra, topic] })
    console.log(`Subscribed to "${topic}".`)
    console.log("Restart the daemon to apply: brew services restart ntfy-mac")
  } else {
    if (!extra.includes(topic)) {
      console.log(`Topic "${topic}" is not in local additions.`)
      console.log("Server-side subscriptions are managed in the ntfy web UI.")
      process.exit(1)
    }
    await updateStored({ extraTopics: extra.filter((t) => t !== topic) })
    console.log(`Unsubscribed from "${topic}".`)
    console.log("Restart the daemon to apply: brew services restart ntfy-mac")
  }
  process.exit(0)
}

if (command === "config") {
  await handleConfigCommand(process.argv.slice(3))
  process.exit(0)
}

if (command === "doctor") {
  const jsonMode = process.argv.includes("--json")
  await runDoctor(VERSION, jsonMode)
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

// ─── Daemon entry ─────────────────────────────────────────────────────────────

// Bare command: show help unless launched by launchd (ppid 1).
// `ntfy-mac start` is the explicit manual escape hatch.
const isDaemon = command === "start" || (command === undefined && process.ppid === 1)

if (!isDaemon) {
  if (command !== undefined) {
    console.error(`Unknown command: ${command}\n`)
  }
  printHelp()
  process.exit(command === undefined ? 0 : 1)
}

// Prevent concurrent daemon instances
if (!acquirePidLock()) {
  console.error("ntfy-mac: another instance is already running")
  process.exit(1)
}

const config = await loadConfig()
if (!config) {
  // Rate-limit to once per hour — launchd restarts on exit-1 which would
  // otherwise fire a new "Ping" notification on every rapid restart cycle.
  const setupState = await loadState()
  const lastNotified = setupState.lastSetupNotification ?? 0
  if (Date.now() - lastNotified > 60 * 60 * 1000) {
    await sendSetupNotification()
    await saveState({ ...setupState, lastSetupNotification: Date.now() })
  }
  releasePidLock()
  console.error("ntfy-mac is not configured. Run: ntfy-mac setup")
  process.exit(1)
}

// ─── Clean up stale notification helpers ──────────────────────────────────────
// The dev build script syncs ntfy-notify.app to ~/Applications/ which registers
// a second notification source in macOS. When users switch to Homebrew or curl,
// the stale copy causes duplicate entries in System Settings → Notifications.
if (detectInstallMethod() !== "dev") {
  const { existsSync } = await import("fs")
  const { homedir: home } = await import("os")
  const devHelper = `${home()}/Applications/ntfy-notify.app`
  if (existsSync(devHelper)) {
    try {
      await Bun.$`rm -rf ${devHelper}`.quiet()
      console.log("cleaned up stale notification helper from ~/Applications/")
    } catch {}
  }
}

// ─── State + Queue initialization ────────────────────────────────────────────

const stateManager = new StateManager()
await stateManager.load()

const queue = new NotificationQueue(sendNotificationNonBlocking)

process.on("SIGINT", () => {
  queue.destroy()
  releasePidLock()
  process.exit(0)
})
process.on("SIGTERM", () => {
  queue.destroy()
  releasePidLock()
  process.exit(0)
})

// Send success notification if a previous auto-update wrote a pending version
takePendingUpdateNotification()
  .then((version) => {
    if (version) return sendUpdateSuccessNotification(version)
  })
  .catch(() => {})

// Non-blocking update check — never throws
checkForUpdate(stateManager).catch(() => {})

// ─── Message handlers (close over config for sound overrides) ────────────────

const soundOverrides = config.sounds
const dismissOverrides = config.dismiss

async function handleMessage(msg: NtfyMessage): Promise<void> {
  if (isSeen(stateManager.get(), msg.id)) return
  stateManager.update((s) => markSeen(s, msg.id))
  const payload = buildNtfyPayload(msg, soundOverrides, dismissOverrides)
  console.log(`notify: [${msg.topic}] p${msg.priority ?? 3} ${payload.title}`)
  queue.enqueue({
    id: msg.id,
    payload,
    priority: msg.priority ?? 3,
    source: "sse",
    maxAttempts: 3,
  })
}

async function handleMissed(result: MissedMessageResult): Promise<void> {
  if (result.type === "individual") {
    for (const msg of result.messages) await handleMessage(msg)
  } else if (result.type === "summary") {
    await sendSummaryNotification(result.count, result.oldestTopic)
  }
  // silent → do nothing
}

let topics: string[]
try {
  if (config.topics) {
    topics = config.topics
  } else {
    const discovered = await discoverTopics(config)
    const extra = config.extraTopics ?? []
    topics = [...new Set([...discovered, ...extra])]
  }
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

startReminderPoll(queue, stateManager)

await startListener(
  config,
  topics,
  handleMessage,
  handleMissed,
  stateManager,
  sendConnectionFailureNotification,
)
