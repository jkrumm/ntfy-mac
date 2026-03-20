import { EMOJI_MAP } from "./emojis"
import type { NtfyMessage } from "./types"

const DEBUG = process.env.NTFY_DEBUG === "1"

const SOUND: Record<number, string | null> = {
  5: "Sosumi",
  4: "Ping",
  3: "Pop",
  2: null,
  1: null,
}

export function getSound(priority?: number): string | null {
  if (priority === undefined) return SOUND[3]
  return SOUND[priority] ?? null
}

export function renderTags(tags?: string[]): string {
  if (!tags || tags.length === 0) return ""
  return tags.map((t) => EMOJI_MAP[t] ?? t).join(" ")
}

export function capitalize(text: string): string {
  if (!text) return text
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function sanitize(text: string): string {
  return text.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
}

interface OsaParams {
  title: string
  subtitle?: string
  body: string
  sound?: string | null
}

export function buildOsaScript(params: OsaParams): string {
  const title = sanitize(params.title)
  const body = sanitize(params.body)
  let script = `display notification "${body}" with title "${title}"`
  if (params.subtitle) script += ` subtitle "${sanitize(params.subtitle)}"`
  if (params.sound) script += ` sound name "${params.sound}"`
  return script
}

export async function sendNotification(msg: NtfyMessage): Promise<void> {
  const title = msg.title ?? capitalize(msg.topic)
  const tags = renderTags(msg.tags)
  const subtitle = tags ? `${msg.topic} • ${tags}` : msg.topic
  const sound = getSound(msg.priority)

  const script = buildOsaScript({ title, subtitle, body: msg.message, sound })
  console.log(`notify: [${msg.topic}] ${title}`)
  if (DEBUG) console.log(`[debug] script: ${script}`)
  const result = await Bun.$`osascript -e ${script}`.quiet()
  if (result.exitCode !== 0) {
    console.error(`notify: osascript failed (exit ${result.exitCode}):`, result.stderr.toString())
  }

  if (msg.click) {
    // Only open http/https URLs — guard against file://, terminal://, etc.
    // Wrap in try/catch: new URL() throws on malformed URLs.
    try {
      const protocol = new URL(msg.click).protocol
      if (protocol === "http:" || protocol === "https:") {
        await Bun.$`open ${msg.click}`.quiet()
      }
    } catch {
      console.error(`notify: invalid click URL — ${msg.click}`)
    }
  }
}

export async function sendSummaryNotification(count: number, oldestTopic: string): Promise<void> {
  const script = buildOsaScript({
    title: "ntfy-mac",
    subtitle: "Open ntfy to review",
    body: `${count} notifications while you were away (${oldestTopic})`,
    sound: "Pop",
  })
  await Bun.$`osascript -e ${script}`.quiet()
}

export async function sendSetupNotification(): Promise<void> {
  const script = buildOsaScript({
    title: "ntfy-mac setup required",
    body: "Run: ntfy-mac setup",
    sound: "Ping",
  })
  await Bun.$`osascript -e ${script}`.quiet()
}

export async function sendConnectionFailureNotification(): Promise<void> {
  const script = buildOsaScript({
    title: "ntfy-mac: connection lost",
    body: "Failed to connect to ntfy server. Check logs or run ntfy-mac setup.",
    sound: "Sosumi",
  })
  await Bun.$`osascript -e ${script}`.quiet()
}

export async function sendUpdateAvailableNotification(
  version: string,
  upgradeCommand: string,
): Promise<void> {
  const script = buildOsaScript({
    title: `ntfy-mac ${version} available`,
    body: upgradeCommand,
  })
  await Bun.$`osascript -e ${script}`.quiet()
}

export async function sendUpdateSuccessNotification(version: string): Promise<void> {
  const script = buildOsaScript({
    title: `ntfy-mac updated to ${version}`,
    body: "Restarted automatically.",
    sound: "Pop",
  })
  await Bun.$`osascript -e ${script}`.quiet()
}
