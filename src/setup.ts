import { createInterface } from "readline"
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
  const res = await fetch(`${url}/v1/account`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (res.status === 401) throw new Error("Authentication failed (401) — check your token")
  if (res.status === 404) throw new Error("Endpoint not found (404) — is this a ntfy server?")
  if (!res.ok) throw new Error(`Server returned ${res.status}`)
  const body = (await res.json()) as { subscriptions?: { topic: string }[] }
  return (body.subscriptions ?? []).map((s) => s.topic)
}

// ─── Brew service start ───────────────────────────────────────────────────────

async function startBrewService(): Promise<boolean> {
  process.stdout.write("Starting service... ")
  try {
    await Bun.$`brew services start jkrumm/tap/ntfy-mac`.quiet()
    console.log("✓")
    return true
  } catch {
    console.log("✗")
    console.log("Could not start service automatically. Run manually:")
    console.log("  brew services start jkrumm/tap/ntfy-mac")
    return false
  }
}

// ─── Keychain save ────────────────────────────────────────────────────────────

async function saveToKeychain(url: string, token: string): Promise<void> {
  await Bun.secrets.set({ service: "ntfy-mac", name: "url", value: url })
  await Bun.secrets.set({ service: "ntfy-mac", name: "token", value: token })
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
    await saveToKeychain(normalized, token)
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error(`Error: could not save credentials to Keychain — ${message}`)
    console.error("Set NTFY_URL and NTFY_TOKEN environment variables instead.")
    process.exit(1)
  }

  console.log(`Configured: ${normalized} (${topics.length} topic(s))`)

  if (detectInstallMethod() === "brew") {
    await startBrewService()
  }
}

// ─── Interactive setup wizard ─────────────────────────────────────────────────

export async function runSetup(): Promise<void> {
  console.log("")
  console.log("ntfy-mac setup")
  console.log("═".repeat(40))
  console.log("Configure your ntfy server credentials.")
  console.log("Credentials are stored in macOS Keychain.")
  console.log("")

  let config: Config | null = null

  while (!config) {
    // Step 1: URL (validated before asking for token)
    const rawUrl = await ask("ntfy server URL", "https://ntfy.example.com")
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
        console.log(`Found ${topics.length} subscribed topic(s):`)
        for (const t of topics) console.log(`  • ${t}`)
      } else {
        console.log("No subscribed topics found.")
        console.log("Subscribe to topics in your ntfy app first.")
      }
      console.log("")

      try {
        await saveToKeychain(url, token)
        console.log("Credentials saved to macOS Keychain.")
      } catch {
        console.log("Warning: could not save to Keychain.")
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

  console.log("")
  console.log("Setup complete!")
  console.log("")

  if (detectInstallMethod() === "brew") {
    const started = await startBrewService()
    if (started) console.log("ntfy-mac is running and will auto-start at login.")
  } else {
    console.log("Start the daemon:")
    console.log("  launchctl load -w ~/Library/LaunchAgents/com.jkrumm.ntfy-mac.plist")
  }
  console.log("")
}
