/**
 * Installation cleanup — ensures only one clean installation exists.
 *
 * ntfy-mac can be installed via Homebrew, curl script, or run from source (dev).
 * Each method places helpers, binaries, and LaunchAgents in different locations.
 * The active install method wins: all artifacts from other methods are removed.
 *
 * Called on: daemon startup, setup, update, doctor.
 * Idempotent and best-effort: safe to call repeatedly, never throws.
 */

import { existsSync } from "fs"
import { homedir } from "os"
import { join } from "path"
import { resolveHelperPath } from "./notifications"
import { detectInstallMethod } from "./updater"

const LSREGISTER =
  "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

// Known artifact locations by install method
const CURL_PLIST = join(homedir(), "Library", "LaunchAgents", "com.jkrumm.ntfy-mac.plist")
const CURL_BINARY = join(homedir(), ".local", "bin", "ntfy-mac")
const CURL_HELPER = join(homedir(), ".local", "share", "ntfy-mac", "ntfy-notify.app")
const DEV_HELPER = join(homedir(), "Applications", "ntfy-notify.app")

/** Returns the .app bundle directory (parent of Contents/MacOS/ntfy-notify). */
export function resolveHelperAppPath(): string {
  return join(resolveHelperPath(), "..", "..", "..")
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function tryRemove(path: string): Promise<boolean> {
  if (!existsSync(path)) return false
  try {
    await Bun.$`rm -rf ${path}`.quiet()
    return true
  } catch {
    return false
  }
}

async function findStaleRegistrations(currentAppPath: string): Promise<string[]> {
  try {
    const result = await Bun.$`${LSREGISTER} -dump | grep -o '/[^ ]*ntfy-notify\\.app'`.quiet()
    const paths = [...new Set(result.stdout.toString().trim().split("\n").filter(Boolean))]
    return paths.filter((p) => p !== currentAppPath)
  } catch {
    return [] // grep exits 1 when no matches
  }
}

// ─── Main cleanup ────────────────────────────────────────────────────────────

/**
 * Ensures a clean, single-method installation. The active install method wins.
 *
 * Cleans up:
 * - Stale helper .app copies from other install methods
 * - Stale curl binary and LaunchAgent (when brew is active)
 * - All stale Launch Services registrations
 * - Re-registers the current helper
 *
 * Returns a list of human-readable actions taken (empty = already clean).
 */
export async function ensureCleanInstallation(): Promise<string[]> {
  const method = detectInstallMethod()
  const currentAppPath = resolveHelperAppPath()
  const actions: string[] = []

  // ── Remove conflicting artifacts from other install methods ────────────────

  if (method === "brew") {
    // Brew is active → remove curl daemon, binary, and helper
    if (existsSync(CURL_PLIST)) {
      try {
        await Bun.$`launchctl unload -w ${CURL_PLIST}`.quiet()
      } catch {} // may not be loaded
      if (await tryRemove(CURL_PLIST)) actions.push("removed curl LaunchAgent")
    }
    if (await tryRemove(CURL_BINARY)) actions.push("removed curl binary")
    if (await tryRemove(CURL_HELPER)) actions.push("removed curl helper")
  }

  // Non-dev → remove dev helper (~/Applications/ntfy-notify.app)
  if (method !== "dev") {
    if (await tryRemove(DEV_HELPER)) actions.push("removed dev helper")
  }

  // ── Clean Launch Services registrations ────────────────────────────────────

  const stale = await findStaleRegistrations(currentAppPath)
  for (const path of stale) {
    try {
      await Bun.$`${LSREGISTER} -u ${path}`.quiet()
    } catch {}
  }
  if (stale.length > 0) actions.push(`cleaned ${stale.length} stale LS registration(s)`)

  // Always re-register current helper to ensure it's up to date
  try {
    await Bun.$`${LSREGISTER} -f ${currentAppPath}`.quiet()
  } catch {}

  return actions
}
