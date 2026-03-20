import { EMOJI_MAP } from "./emojis"
import {
  NotificationBuilder,
  sendNotificationPayload,
  type NotificationAction,
  type SystemSound,
  type InterruptionLevel,
} from "./notifications"
import type { NtfyMessage } from "./types"

// ─── Priority config ──────────────────────────────────────────────────────────

interface PriorityConfig {
  sound: SystemSound | null
  interruptionLevel: InterruptionLevel
  relevanceScore: number
}

export const PRIORITY_CONFIG: Record<number, PriorityConfig> = {
  5: { sound: "Sosumi", interruptionLevel: "time-sensitive", relevanceScore: 1.0 },
  4: { sound: "Ping", interruptionLevel: "time-sensitive", relevanceScore: 0.75 },
  3: { sound: "Pop", interruptionLevel: "active", relevanceScore: 0.5 },
  2: { sound: null, interruptionLevel: "active", relevanceScore: 0.25 },
  1: { sound: null, interruptionLevel: "passive", relevanceScore: 0.0 },
}

export function getSound(priority?: number): SystemSound | null {
  return (PRIORITY_CONFIG[priority ?? 3] ?? PRIORITY_CONFIG[3]).sound
}

// ─── Tag rendering ────────────────────────────────────────────────────────────

export function renderTags(tags?: string[]): string {
  if (!tags || tags.length === 0) return ""
  return tags.map((t) => EMOJI_MAP[t] ?? t).join(" ")
}

// ─── Text helpers ─────────────────────────────────────────────────────────────

export function capitalize(text: string): string {
  if (!text) return text
  return text.charAt(0).toUpperCase() + text.slice(1)
}

// ─── Action mapping ───────────────────────────────────────────────────────────

export function mapActions(msg: NtfyMessage): NotificationAction[] {
  if (!msg.actions) return []
  const result: NotificationAction[] = []
  const seenIds = new Set<string>()
  for (const a of msg.actions) {
    if (a.action !== "view" && a.action !== "http") continue
    const base = `${a.action}-${a.label.toLowerCase().replace(/\s+/g, "-")}`
    let id = base
    let n = 1
    while (seenIds.has(id)) id = `${base}-${n++}`
    seenIds.add(id)
    const action: NotificationAction = {
      identifier: id,
      title: a.label,
    }
    if (a.action === "view" && a.url) {
      action.url = a.url
    } else if (a.action === "http" && a.url) {
      action.httpUrl = a.url
      action.httpMethod = a.method ?? "POST"
      if (a.headers) action.httpHeaders = a.headers
      if (a.body) action.httpBody = a.body
    }
    result.push(action)
  }
  return result
}

// ─── Image URL selection ──────────────────────────────────────────────────────

export function selectImageUrl(msg: NtfyMessage): string | undefined {
  if (msg.attachment?.url && msg.attachment.type?.startsWith("image/")) {
    return msg.attachment.url
  }
  return msg.icon
}

// ─── Payload builder (exported for tests) ────────────────────────────────────

export interface NtfyNotificationPayload {
  title: string
  subtitle: string
  body: string
  sound: SystemSound | null
  threadId: string
  interruptionLevel: InterruptionLevel
  relevanceScore: number
  clickUrl?: string
  imageUrl?: string
  actions?: NotificationAction[]
  categoryId?: string
}

export function buildNtfyPayload(msg: NtfyMessage): NtfyNotificationPayload {
  const title = msg.title ?? capitalize(msg.topic)
  const tags = renderTags(msg.tags)
  const subtitle = tags ? `${msg.topic} • ${tags}` : msg.topic
  const { sound, interruptionLevel, relevanceScore } =
    PRIORITY_CONFIG[msg.priority ?? 3] ?? PRIORITY_CONFIG[3]

  const payload: NtfyNotificationPayload = {
    title,
    subtitle,
    body: msg.message,
    sound,
    threadId: msg.topic,
    interruptionLevel,
    relevanceScore,
  }

  if (msg.click) payload.clickUrl = msg.click

  const imageUrl = selectImageUrl(msg)
  if (imageUrl) payload.imageUrl = imageUrl

  const actions = mapActions(msg)
  if (actions.length > 0) {
    payload.actions = actions
    payload.categoryId = `ntfy-${msg.id.slice(0, 8)}`
  }

  return payload
}

// ─── Notification senders ─────────────────────────────────────────────────────

export async function sendNotification(msg: NtfyMessage): Promise<void> {
  const payload = buildNtfyPayload(msg)
  console.log(`notify: [${msg.topic}] ${payload.title}`)
  await sendNotificationPayload(payload)
}

export async function sendSummaryNotification(count: number, oldestTopic: string): Promise<void> {
  await new NotificationBuilder(
    "ntfy-mac",
    `${count} notifications while you were away (${oldestTopic})`,
  )
    .subtitle("Open ntfy to review")
    .sound("Pop")
    .send()
}

export async function sendSetupNotification(): Promise<void> {
  await new NotificationBuilder("ntfy-mac setup required", "Run: ntfy-mac setup")
    .sound("Ping")
    .interruptionLevel("time-sensitive")
    .send()
}

export async function sendConnectionFailureNotification(): Promise<void> {
  await new NotificationBuilder(
    "ntfy-mac: connection lost",
    "Failed to connect to ntfy server. Check logs or run ntfy-mac setup.",
  )
    .sound("Sosumi")
    .interruptionLevel("time-sensitive")
    .send()
}

export async function sendUpdateAvailableNotification(
  version: string,
  upgradeCommand: string,
): Promise<void> {
  await new NotificationBuilder(`ntfy-mac ${version} available`, upgradeCommand)
    .sound(null)
    .interruptionLevel("passive")
    .send()
}

export async function sendUpdateSuccessNotification(version: string): Promise<void> {
  await new NotificationBuilder(`ntfy-mac updated to ${version}`, "Restarted automatically.")
    .sound("Pop")
    .interruptionLevel("passive")
    .send()
}
