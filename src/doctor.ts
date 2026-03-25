import { existsSync, statSync } from "fs"
import { homedir } from "os"
import { CONFIG_PATH, loadConfig } from "./config"
import { ensureCleanInstallation, resolveHelperAppPath } from "./launchservices"
import { resolveHelperPath } from "./notifications"
import { loadState } from "./state"
import { discoverTopics } from "./ntfy"
import { PRIORITY_CONFIG } from "./notify"
import { detectInstallMethod, isNewerVersion } from "./updater"

// ─── Types ───────────────────────────────────────────────────────────────────

interface CheckResult {
  name: string
  status: "ok" | "warn" | "fail"
  message: string
  detail?: string
}

interface DoctorReport {
  version: string
  installMethod: string
  checks: CheckResult[]
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function fileSize(path: string): number | null {
  try {
    return statSync(path).size
  } catch {
    return null
  }
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function logPaths(installMethod: string): { stdout: string; stderr: string } {
  if (installMethod === "brew") {
    const prefix = process.env.HOMEBREW_PREFIX ?? "/opt/homebrew"
    return {
      stdout: `${prefix}/var/log/ntfy-mac.log`,
      stderr: `${prefix}/var/log/ntfy-mac-error.log`,
    }
  }
  const stateDir = `${homedir()}/.local/share/ntfy-mac`
  return {
    stdout: `${stateDir}/ntfy-mac.log`,
    stderr: `${stateDir}/ntfy-mac-error.log`,
  }
}

// ─── Individual checks ──────────────────────────────────────────────────────

async function checkConfig(): Promise<CheckResult> {
  if (!existsSync(CONFIG_PATH)) {
    return { name: "config", status: "fail", message: "Config file missing", detail: CONFIG_PATH }
  }
  const config = await loadConfig()
  if (!config) {
    return {
      name: "config",
      status: "fail",
      message: "Config invalid or incomplete",
      detail: "Run: ntfy-mac setup",
    }
  }
  return { name: "config", status: "ok", message: `Server: ${config.url}` }
}

async function checkServer(): Promise<CheckResult> {
  const config = await loadConfig()
  if (!config) {
    return { name: "server", status: "fail", message: "Skipped (no config)" }
  }
  try {
    const res = await fetch(`${config.url}/v1/health`, {
      signal: AbortSignal.timeout(10_000),
    })
    if (res.ok) {
      return { name: "server", status: "ok", message: "Server reachable" }
    }
    return {
      name: "server",
      status: "fail",
      message: `Server returned ${res.status}`,
    }
  } catch (err) {
    return {
      name: "server",
      status: "fail",
      message: `Cannot reach server`,
      detail: err instanceof Error ? err.message : String(err),
    }
  }
}

async function checkAuth(): Promise<CheckResult> {
  const config = await loadConfig()
  if (!config) {
    return { name: "auth", status: "fail", message: "Skipped (no config)" }
  }
  try {
    const res = await fetch(`${config.url}/v1/account`, {
      headers: { Authorization: `Bearer ${config.token}` },
      signal: AbortSignal.timeout(10_000),
    })
    if (res.status === 401) {
      return {
        name: "auth",
        status: "fail",
        message: "Auth failed (401)",
        detail: "Run: ntfy-mac setup",
      }
    }
    if (!res.ok) {
      return { name: "auth", status: "fail", message: `Auth check returned ${res.status}` }
    }
    return { name: "auth", status: "ok", message: "Token valid" }
  } catch (err) {
    return {
      name: "auth",
      status: "warn",
      message: "Could not verify auth",
      detail: err instanceof Error ? err.message : String(err),
    }
  }
}

async function checkTopics(): Promise<CheckResult> {
  const config = await loadConfig()
  if (!config) {
    return { name: "topics", status: "fail", message: "Skipped (no config)" }
  }
  try {
    const discovered = config.topics ?? (await discoverTopics(config))
    const extra = config.extraTopics ?? []
    const topics = [...new Set([...discovered, ...extra])]
    if (topics.length === 0) {
      return {
        name: "topics",
        status: "warn",
        message: "No subscribed topics",
        detail: "Subscribe via: ntfy-mac subscribe <topic>",
      }
    }
    const extraNote = extra.length > 0 ? ` (+${extra.length} local)` : ""
    return {
      name: "topics",
      status: "ok",
      message: `${topics.length} topic(s)${extraNote}: ${topics.join(", ")}`,
    }
  } catch (err) {
    return {
      name: "topics",
      status: "fail",
      message: "Failed to discover topics",
      detail: err instanceof Error ? err.message : String(err),
    }
  }
}

async function checkDaemon(installMethod: string): Promise<CheckResult> {
  try {
    if (installMethod === "brew") {
      const result = await Bun.$`brew services info ntfy-mac --json`.quiet()
      const info = JSON.parse(result.stdout.toString()) as { status?: string }[]
      const status = info[0]?.status
      if (status === "started") {
        return { name: "daemon", status: "ok", message: "Running (brew services)" }
      }
      return {
        name: "daemon",
        status: "warn",
        message: `Not running (status: ${status ?? "unknown"})`,
        detail: "Start with: brew services start ntfy-mac",
      }
    }
    // curl install: check launchctl
    const result = await Bun.$`launchctl list com.jkrumm.ntfy-mac`.quiet()
    if (result.exitCode === 0) {
      return { name: "daemon", status: "ok", message: "Running (launchd)" }
    }
    return {
      name: "daemon",
      status: "warn",
      message: "Not loaded",
      detail: "Start with: launchctl load -w ~/Library/LaunchAgents/com.jkrumm.ntfy-mac.plist",
    }
  } catch {
    return { name: "daemon", status: "warn", message: "Could not determine daemon status" }
  }
}

async function checkState(): Promise<CheckResult> {
  try {
    const state = await loadState()
    const count = Object.keys(state.seen).length
    return {
      name: "state",
      status: "ok",
      message: `${count} dedup entries, last ID: ${state.lastMessageId ?? "(none)"}`,
    }
  } catch (err) {
    return {
      name: "state",
      status: "warn",
      message: "State file unreadable",
      detail: err instanceof Error ? err.message : String(err),
    }
  }
}

function checkLogs(installMethod: string): CheckResult {
  const paths = logPaths(installMethod)
  const stdoutSize = fileSize(paths.stdout)
  const stderrSize = fileSize(paths.stderr)

  if (stdoutSize === null && stderrSize === null) {
    return { name: "logs", status: "warn", message: "No log files found" }
  }

  const parts: string[] = []
  if (stdoutSize !== null) parts.push(`stdout: ${formatBytes(stdoutSize)}`)
  if (stderrSize !== null) parts.push(`stderr: ${formatBytes(stderrSize)}`)

  const totalSize = (stdoutSize ?? 0) + (stderrSize ?? 0)
  const status = totalSize > 50 * 1024 * 1024 ? "warn" : "ok"
  const detail = status === "warn" ? "Logs are large. Consider truncating." : undefined

  return { name: "logs", status, message: parts.join(", "), detail }
}

async function checkUpdate(version: string): Promise<CheckResult> {
  try {
    const res = await fetch("https://api.github.com/repos/jkrumm/ntfy-mac/releases/latest", {
      headers: { "User-Agent": "ntfy-mac" },
      signal: AbortSignal.timeout(10_000),
    })
    if (!res.ok) {
      return { name: "update", status: "warn", message: "Could not check for updates" }
    }
    const body = (await res.json()) as { tag_name?: string }
    const latest = body.tag_name
    if (!latest) {
      return { name: "update", status: "warn", message: "Could not parse latest version" }
    }
    if (isNewerVersion(latest, version)) {
      return {
        name: "update",
        status: "warn",
        message: `Update available: ${latest} (current: ${version})`,
        detail: "Run: ntfy-mac update",
      }
    }
    return { name: "update", status: "ok", message: `Up to date (${version})` }
  } catch {
    return { name: "update", status: "warn", message: "Could not check for updates" }
  }
}

async function checkHelper(): Promise<CheckResult> {
  const helperPath = resolveHelperPath()
  if (!existsSync(helperPath)) {
    return {
      name: "helper",
      status: "fail",
      message: "Notification helper not found",
      detail: `Expected: ${resolveHelperAppPath()}`,
    }
  }

  // Run full installation cleanup — removes stale helpers, LaunchAgents,
  // binaries, and LS registrations from other install methods
  const actions = await ensureCleanInstallation()
  if (actions.length > 0) {
    return {
      name: "helper",
      status: "warn",
      message: `Fixed: ${actions.join(", ")}`,
    }
  }

  return { name: "helper", status: "ok", message: "Clean, no stale artifacts" }
}

function checkDismissConfig(): CheckResult {
  const stored = loadStoredConfigSync()
  const dismiss = stored?.dismiss as Record<string, number> | undefined
  const hasOverrides = dismiss && Object.keys(dismiss).length > 0
  const parts: string[] = []
  for (let p = 5; p >= 1; p--) {
    const override = dismiss?.[String(p)]
    const effective = override !== undefined ? override : (PRIORITY_CONFIG[p]?.dismissAfter ?? 0)
    parts.push(`p${p}: ${effective === 0 ? "never" : effective + "s"}`)
  }
  return {
    name: "dismiss",
    status: "ok",
    message: `${hasOverrides ? "Custom" : "Defaults"}: ${parts.join(", ")}`,
    detail: "Configure with: ntfy-mac config dismiss",
  }
}

function checkSounds(): CheckResult {
  const stored = loadStoredConfigSync()
  const sounds = stored?.sounds as Record<string, string | null> | undefined
  if (!sounds || Object.keys(sounds).length === 0) {
    return { name: "sounds", status: "ok", message: "Using defaults" }
  }
  const customCount = Object.keys(sounds).length
  return {
    name: "sounds",
    status: "ok",
    message: `${customCount} custom sound(s) configured`,
    detail: "View with: ntfy-mac config sounds",
  }
}

// Sync version for checks that don't need async
function loadStoredConfigSync(): Record<string, unknown> | null {
  try {
    const text = require("fs").readFileSync(CONFIG_PATH, "utf-8")
    return JSON.parse(text)
  } catch {
    return null
  }
}

// ─── Doctor runner ───────────────────────────────────────────────────────────

export async function runDoctor(version: string, jsonMode: boolean): Promise<void> {
  const installMethod = detectInstallMethod()

  const checks = await Promise.all([
    checkConfig(),
    checkServer(),
    checkAuth(),
    checkTopics(),
    checkDaemon(installMethod),
    checkHelper(),
    checkState(),
    Promise.resolve(checkLogs(installMethod)),
    checkUpdate(version),
    Promise.resolve(checkDismissConfig()),
    Promise.resolve(checkSounds()),
  ])

  const report: DoctorReport = { version, installMethod, checks }

  if (jsonMode) {
    console.log(JSON.stringify(report, null, 2))
    return
  }

  // Human-readable output
  console.log(`ntfy-mac doctor (${version})\n`)

  const icons = { ok: "✓", warn: "!", fail: "✗" }

  for (const check of checks) {
    const icon = icons[check.status]
    const pad = check.name.padEnd(15)
    console.log(`  ${icon} ${pad} ${check.message}`)
    if (check.detail) {
      console.log(`${"".padEnd(19)}${check.detail}`)
    }
  }

  const failures = checks.filter((c) => c.status === "fail").length
  const warnings = checks.filter((c) => c.status === "warn").length

  console.log("")
  if (failures > 0) {
    console.log(`${failures} issue(s) found. Fix them and run again.`)
  } else if (warnings > 0) {
    console.log(`All good, ${warnings} suggestion(s).`)
  } else {
    console.log("Everything looks good.")
  }
}
