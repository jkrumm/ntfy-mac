import { dirname } from "path"
import { createInterface } from "readline"
import { CONFIG_PATH } from "./config"
import { sendNotificationPayload } from "./notifications"
import { detectInstallMethod } from "./updater"
import type { Config } from "./types"

// ─── Input helpers ───────────────────────────────────────────────────────────

function ask(question: string, defaultValue?: string): Promise<string> {
  return new Promise((resolve) => {
    const suffix = defaultValue ? ` [${defaultValue}]: ` : ": "
    const rl = createInterface({ input: process.stdin, output: process.stdout })
    rl.question(question + suffix, (answer) => {
      rl.close()
      resolve(answer.trim() || defaultValue || "")
    })
  })
}

async function askSecret(question: string, hint?: string): Promise<string> {
  if (hint) console.log(hint)
  process.stdout.write(question + ": ")
  // Disable terminal echo so the token is not visible while typing.
  // Guard: stty only works on a real TTY; skip silently in piped contexts.
  const isTTY = process.stdin.isTTY === true
  if (isTTY) await Bun.$`stty -echo`.quiet()
  try {
    const answer = await new Promise<string>((resolve) => {
      const rl = createInterface({ input: process.stdin })
      rl.once("line", (line) => {
        rl.close()
        resolve(line.trim())
      })
    })
    return answer
  } finally {
    if (isTTY) await Bun.$`stty echo`.quiet()
    process.stdout.write("\n")
  }
}

// ─── URL normalisation ────────────────────────────────────────────────────────

function normalizeUrl(input: string): string {
  const trimmed = input.trim().replace(/\/$/, "")
  if (!trimmed) return trimmed
  // Auto-prepend https:// if no protocol given
  if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
    return `https://${trimmed}`
  }
  return trimmed
}

function validateUrl(url: string): string | null {
  try {
    const parsed = new URL(url)
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return `Protocol must be http or https (got ${parsed.protocol})`
    }
    return null
  } catch {
    return `Invalid URL: ${url}`
  }
}

// ─── Connection test ─────────────────────────────────────────────────────────

async function testConnection(url: string, token: string): Promise<string[]> {
  let res: Response
  try {
    res = await fetch(`${url}/v1/account`, {
      headers: { Authorization: `Bearer ${token}` },
    })
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    throw new Error(`Could not reach server — ${msg}`)
  }
  if (res.status === 401) throw new Error("Authentication failed (401) — check your token")
  if (res.status === 404) throw new Error("Endpoint not found (404) — is this a ntfy server?")
  if (!res.ok) throw new Error(`Server returned ${res.status}`)
  let body: { subscriptions?: { topic: string }[] }
  try {
    body = (await res.json()) as { subscriptions?: { topic: string }[] }
  } catch {
    throw new Error("Server did not return valid JSON — is this a ntfy server?")
  }
  return (body.subscriptions ?? []).map((s) => s.topic)
}

// ─── Brew service start ───────────────────────────────────────────────────────

async function startBrewService(): Promise<boolean> {
  process.stdout.write("Starting service... ")
  try {
    // Use restart rather than start — handles both fresh installs and upgrades
    // where Homebrew may have already started the service automatically.
    await Bun.$`brew services restart jkrumm/tap/ntfy-mac`.quiet()
    console.log("✓")
    return true
  } catch {
    console.log("✗")
    console.log("Could not start service automatically. Run manually:")
    console.log("  brew services restart jkrumm/tap/ntfy-mac")
    return false
  }
}

// ─── Config file save ─────────────────────────────────────────────────────────

async function saveConfig(url: string, token: string): Promise<void> {
  const dir = dirname(CONFIG_PATH)
  await Bun.$`mkdir -p ${dir}`.quiet()
  const prevUmask = process.umask(0o077)
  await Bun.write(CONFIG_PATH, JSON.stringify({ url, token }, null, 2))
  process.umask(prevUmask)
}

// ─── Non-interactive setup ────────────────────────────────────────────────────

export async function runSetupNonInteractive(url: string, token: string): Promise<void> {
  const normalized = normalizeUrl(url)
  const urlError = validateUrl(normalized)
  if (urlError) {
    console.error(`Error: ${urlError}`)
    process.exit(1)
  }

  process.stdout.write("Testing connection... ")
  let topics: string[]
  try {
    topics = await testConnection(normalized, token)
    console.log("✓")
  } catch (err) {
    console.log("✗")
    const message = err instanceof Error ? err.message : String(err)
    console.error(`Connection failed: ${message}`)
    process.exit(1)
  }

  try {
    await saveConfig(normalized, token)
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error(`Error: could not save credentials — ${message}`)
    console.error("Set NTFY_URL and NTFY_TOKEN environment variables instead.")
    process.exit(1)
  }

  console.log(`Configured: ${normalized} (${topics.length} topic(s))`)

  if (detectInstallMethod() === "brew") {
    await startBrewService()
  }

  await sendNotificationPayload({
    title: "ntfy-mac is ready",
    body: `Listening on ${topics.length} topic(s). Notifications are active.`,
    sound: "Pop",
    interruptionLevel: "active",
  })
}

// ─── Interactive setup wizard ─────────────────────────────────────────────────

export async function runSetup(): Promise<void> {
  console.log("")
  console.log("ntfy-mac setup")
  console.log("═".repeat(40))
  console.log("Configure your ntfy server credentials.")
  console.log("")

  let config: Config | null = null

  while (!config) {
    // Step 1: URL (validated before asking for token)
    const rawUrl = await ask("ntfy server URL", "ntfy.example.com")
    if (!rawUrl) {
      console.log("URL is required.\n")
      continue
    }

    const url = normalizeUrl(rawUrl)
    const urlError = validateUrl(url)
    if (urlError) {
      console.log(`${urlError}\n`)
      continue
    }

    // Step 2: Token (shown only after URL is valid)
    const token = await askSecret(
      "Auth token",
      `  → Get your token at ${url}/account → Access Tokens`,
    )

    if (!token) {
      console.log("Token is required.\n")
      continue
    }

    // Step 3: Test connection
    process.stdout.write("\nTesting connection... ")
    try {
      const topics = await testConnection(url, token)
      console.log("✓\n")

      if (topics.length > 0) {
        const noun = topics.length === 1 ? "topic" : "topics"
        console.log(`Subscribed to ${topics.length} ${noun}:`)
        for (const t of topics) console.log(`  • ${t}`)
      } else {
        console.log("No subscribed topics found.")
        console.log("Subscribe to topics in your ntfy app first.")
      }
      console.log("")

      try {
        await saveConfig(url, token)
      } catch {
        console.log("Warning: could not save credentials.")
        console.log("Set NTFY_URL and NTFY_TOKEN environment variables instead.")
      }

      config = { url, token, topics: topics.length > 0 ? topics : undefined }
    } catch (err) {
      console.log("✗\n")
      const message = err instanceof Error ? err.message : String(err)
      console.log(`Connection failed: ${message}\n`)

      const retry = await ask("Retry? (y/n)", "y")
      if (retry.toLowerCase() !== "y") {
        console.log("Setup cancelled.")
        process.exit(1)
      }
      console.log("")
    }
  }

  if (detectInstallMethod() === "brew") {
    const started = await startBrewService()
    console.log(started ? "\nSetup complete! ntfy-mac is running." : "\nSetup complete!")
  } else {
    const plist = `${process.env.HOME}/Library/LaunchAgents/com.jkrumm.ntfy-mac.plist`
    try {
      await Bun.$`launchctl load -w ${plist}`.quiet()
      console.log("\nSetup complete! ntfy-mac is running.")
    } catch {
      console.log("\nSetup complete!")
      console.log("Start the daemon:")
      console.log("  launchctl load -w ~/Library/LaunchAgents/com.jkrumm.ntfy-mac.plist")
    }
  }

  console.log("")
  console.log("┌─────────────────────────────────────────────────────┐")
  console.log("│  A macOS permission dialog will appear now.         │")
  console.log("│  Click Allow to enable ntfy-mac notifications.      │")
  console.log("│                                                     │")
  console.log("│  If you miss it: System Settings → Notifications    │")
  console.log("│  → ntfy-mac → enable                                │")
  console.log("└─────────────────────────────────────────────────────┘")
  console.log("")

  await sendNotificationPayload({
    title: "ntfy-mac is ready",
    body: `Listening on ${config.topics?.length ?? 0} topic(s). Notifications are active.`,
    sound: "Pop",
    interruptionLevel: "active",
  })
}
