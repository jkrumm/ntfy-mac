import { createInterface } from "readline"
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

async function askSecret(question: string): Promise<string> {
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

// ─── Keychain save ────────────────────────────────────────────────────────────

async function saveToKeychain(url: string, token: string): Promise<void> {
  await Bun.secrets.set({ service: "ntfy-mac", name: "url", value: url })
  await Bun.secrets.set({ service: "ntfy-mac", name: "token", value: token })
}

// ─── Setup wizard ─────────────────────────────────────────────────────────────

export async function runSetup(): Promise<void> {
  console.log("")
  console.log("ntfy-mac setup")
  console.log("═".repeat(40))
  console.log("Configure your ntfy server credentials.")
  console.log("Credentials are stored in macOS Keychain.")
  console.log("")

  let config: Config | null = null

  while (!config) {
    const url = await ask("ntfy server URL", "https://ntfy.example.com")
    const token = await askSecret("Auth token")

    if (!url || !token) {
      console.log("URL and token are required.\n")
      continue
    }

    // Basic URL validation
    try {
      const parsed = new URL(url)
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
        console.log(`Invalid URL protocol: ${parsed.protocol}. Use http or https.\n`)
        continue
      }
    } catch {
      console.log(`Invalid URL: ${url}\n`)
      continue
    }

    const cleanUrl = url.replace(/\/$/, "")

    process.stdout.write("\nTesting connection... ")
    try {
      const topics = await testConnection(cleanUrl, token)
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
        await saveToKeychain(cleanUrl, token)
        console.log("Credentials saved to macOS Keychain.")
      } catch {
        console.log("Warning: could not save to Keychain.")
        console.log("Set NTFY_URL and NTFY_TOKEN environment variables instead.")
      }

      config = { url: cleanUrl, token, topics: topics.length > 0 ? topics : undefined }
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
  console.log("Setup complete! Start receiving notifications:")
  console.log("")
  console.log("  brew services start ntfy-mac")
  console.log("")
  console.log("To run manually:")
  console.log("  ntfy-mac")
  console.log("")
}
