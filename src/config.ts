import type { Config } from "./types"

export async function loadConfig(): Promise<Config | null> {
  let url: string | null = null
  let token: string | null = null

  // Try Keychain first via Bun.secrets
  try {
    url = (await Bun.secrets.get({ service: "ntfy-mac", name: "url" })) ?? null
    token = (await Bun.secrets.get({ service: "ntfy-mac", name: "token" })) ?? null
  } catch {
    // Bun.secrets unavailable (e.g. not running as a compiled binary on macOS)
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
