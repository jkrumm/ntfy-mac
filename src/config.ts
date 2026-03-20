import { homedir } from "os"
import { join } from "path"
import type { Config } from "./types"

export const CONFIG_PATH = join(homedir(), ".config", "ntfy-mac", "config.json")

type StoredConfig = { url: string; token: string }

export async function loadConfig(): Promise<Config | null> {
  let url: string | null = null
  let token: string | null = null

  // Try config file first
  try {
    const file = Bun.file(CONFIG_PATH)
    if (await file.exists()) {
      const stored = (await file.json()) as StoredConfig
      url = stored.url ?? null
      token = stored.token ?? null
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

  return { url: url.replace(/\/$/, ""), token: token.trim(), topics }
}
