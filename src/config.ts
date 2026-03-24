import { homedir } from "os"
import { join } from "path"
import type { Config } from "./types"

export const CONFIG_PATH = join(homedir(), ".config", "ntfy-mac", "config.json")

export async function loadConfig(): Promise<Config | null> {
  let url: string | null = null
  let token: string | null = null
  let sounds: Config["sounds"]
  let dismiss: Config["dismiss"]
  let extraTopics: Config["extraTopics"]

  // Try config file first
  try {
    const file = Bun.file(CONFIG_PATH)
    if (await file.exists()) {
      const stored = (await file.json()) as Record<string, unknown>
      url = (stored.url as string) ?? null
      token = (stored.token as string) ?? null
      sounds = (stored.sounds as Config["sounds"]) ?? undefined
      dismiss = (stored.dismiss as Config["dismiss"]) ?? undefined
      extraTopics = (stored.extraTopics as string[]) ?? undefined
    }
  } catch {
    // Config file unreadable or malformed
  }

  // Fall back to environment variables
  if (!url) url = process.env.NTFY_URL ?? null
  if (!token) token = process.env.NTFY_TOKEN ?? null

  if (!url || !token) return null

  // Validate URL
  try {
    const parsed = new URL(url)
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      console.error(`Invalid NTFY URL protocol: ${parsed.protocol}. Must be http or https.`)
      return null
    }
  } catch {
    console.error(`Invalid NTFY URL: ${url}`)
    return null
  }

  // Validate token
  if (token.trim().length === 0) {
    console.error("NTFY token must not be empty.")
    return null
  }

  // Parse optional topics override
  const topicsEnv = process.env.NTFY_TOPICS
  const topics = topicsEnv
    ? topicsEnv
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean)
    : undefined

  return { url: url.replace(/\/$/, ""), token: token.trim(), topics, extraTopics, sounds, dismiss }
}

/** Read the raw stored config from disk (returns empty object if missing/malformed). */
export async function loadStoredConfig(): Promise<Record<string, unknown>> {
  try {
    const file = Bun.file(CONFIG_PATH)
    if (await file.exists()) return (await file.json()) as Record<string, unknown>
  } catch {
    // Unreadable or malformed
  }
  return {}
}

/** Merge fields into the stored config file without overwriting unrelated keys. */
export async function updateStoredConfig(fields: Record<string, unknown>): Promise<void> {
  const existing = await loadStoredConfig()
  const merged = { ...existing, ...fields }
  const { mkdirSync } = await import("fs")
  const { dirname } = await import("path")
  mkdirSync(dirname(CONFIG_PATH), { recursive: true })
  await Bun.write(CONFIG_PATH, JSON.stringify(merged, null, 2) + "\n")
}
