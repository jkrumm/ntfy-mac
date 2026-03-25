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

interface RemoveResult {
  ok: boolean
  error?: string
}

async function tryRemove(path: string): Promise<RemoveResult> {
  if (!existsSync(path)) return { ok: false }
  try {
    await Bun.$`rm -rf ${path}`.quiet()
    return { ok: true }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return { ok: false, error: `Failed to remove ${path}: ${msg}` }
  }
}

interface StaleRegistrationsResult {
  paths: string[]
  error?: string
}

async function findStaleRegistrations(currentAppPath: string): Promise<StaleRegistrationsResult> {
  try {
    const result = await Bun.$`${LSREGISTER} -dump | grep -o '/[^ ]*ntfy-notify\\.app'`.quiet()
    const paths = [...new Set(result.stdout.toString().trim().split("\n").filter(Boolean))]
    return { paths: paths.filter((p) => p !== currentAppPath) }
  } catch (err) {
    // grep exits 1 when no matches, but other errors should be reported
    const msg = err instanceof Error ? err.message : String(err)
    // Only report if it looks like a real error (not "no matches")
    const isNoMatches = msg.includes("exit code 1")
    return {
      paths: [],
      error: isNoMatches ? undefined : `Failed to find stale registrations: ${msg}`,
    }
  }
}

// ─── Main cleanup ────────────────────────────────────────────────────────────

export interface CleanupResult {
  actions: string[]
  errors: string[]
}

/**
 * Ensures a clean, single-method installation. The active install method wins.
 *
 * Cleans up:
 * - Stale helper .app copies from other install methods
 * - Stale curl binary and LaunchAgent (when brew is active)
 * - All stale Launch Services registrations
 * - Re-registers the current helper
 *
 * Returns actions taken and any errors encountered. Empty actions = already clean.
 * Errors = operations failed (but best-effort continues).
 */
export async function ensureCleanInstallation(): Promise<CleanupResult> {
  const method = detectInstallMethod()
  const currentAppPath = resolveHelperAppPath()
  const actions: string[] = []
  const errors: string[] = []

  // ── Remove conflicting artifacts from other install methods ────────────────

  // Brew is active → remove curl and dev artifacts
  if (method === "brew") {
    // Remove curl daemon, binary, and helper
    if (existsSync(CURL_PLIST)) {
      try {
        await Bun.$`launchctl unload -w ${CURL_PLIST}`.quiet()
      } catch {} // may not be loaded
      const res = await tryRemove(CURL_PLIST)
      if (res.ok) actions.push("removed curl LaunchAgent")
      else if (res.error) errors.push(res.error)
    }
    const binRes = await tryRemove(CURL_BINARY)
    if (binRes.ok) actions.push("removed curl binary")
    else if (binRes.error) errors.push(binRes.error)
    const helperRes = await tryRemove(CURL_HELPER)
    if (helperRes.ok) actions.push("removed curl helper")
    else if (helperRes.error) errors.push(helperRes.error)
    // Remove dev helper
    const devRes = await tryRemove(DEV_HELPER)
    if (devRes.ok) actions.push("removed dev helper")
    else if (devRes.error) errors.push(devRes.error)
  }

  // Curl is active → remove brew and dev artifacts
  if (method === "curl") {
    const devRes = await tryRemove(DEV_HELPER)
    if (devRes.ok) actions.push("removed dev helper")
    else if (devRes.error) errors.push(devRes.error)
  }

  // Dev is active → remove brew and curl artifacts
  if (method === "dev") {
    // Remove curl daemon, binary, and helper
    if (existsSync(CURL_PLIST)) {
      try {
        await Bun.$`launchctl unload -w ${CURL_PLIST}`.quiet()
      } catch {} // may not be loaded
      const res = await tryRemove(CURL_PLIST)
      if (res.ok) actions.push("removed curl LaunchAgent")
      else if (res.error) errors.push(res.error)
    }
    const binRes = await tryRemove(CURL_BINARY)
    if (binRes.ok) actions.push("removed curl binary")
    else if (binRes.error) errors.push(binRes.error)
    const helperRes = await tryRemove(CURL_HELPER)
    if (helperRes.ok) actions.push("removed curl helper")
    else if (helperRes.error) errors.push(helperRes.error)
  }

  // ── Clean Launch Services registrations ────────────────────────────────────

  const staleRes = await findStaleRegistrations(currentAppPath)
  if (staleRes.error) errors.push(staleRes.error)

  for (const path of staleRes.paths) {
    try {
      await Bun.$`${LSREGISTER} -u ${path}`.quiet()
    } catch (err) {
      errors.push(
        `Failed to unregister ${path}: ${err instanceof Error ? err.message : String(err)}`,
      )
    }
  }
  if (staleRes.paths.length > 0)
    actions.push(`cleaned ${staleRes.paths.length} stale LS registration(s)`)

  // Always re-register current helper to ensure it's up to date
  try {
    await Bun.$`${LSREGISTER} -f ${currentAppPath}`.quiet()
  } catch (err) {
    errors.push(`Failed to re-register helper: ${err instanceof Error ? err.message : String(err)}`)
  }

  return { actions, errors }
}
