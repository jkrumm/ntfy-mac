import { EMOJI_MAP } from "./emojis"
import {
  NotificationBuilder,
  sendNotificationPayload,
  type NotificationAction,
  type SystemSound,
  type InterruptionLevel,
} from "./notifications"
import type { DismissConfig, NtfyMessage, SoundConfig } from "./types"

// ─── Priority config ──────────────────────────────────────────────────────────

interface PriorityConfig {
  sound: SystemSound | null
  interruptionLevel: InterruptionLevel
  relevanceScore: number
  dismissAfter: number // 0 = never auto-dismiss
}

export const PRIORITY_CONFIG: Record<number, PriorityConfig> = {
  5: { sound: "Ping", interruptionLevel: "time-sensitive", relevanceScore: 1.0, dismissAfter: 0 },
  4: { sound: "Ping", interruptionLevel: "time-sensitive", relevanceScore: 0.75, dismissAfter: 0 },
  3: { sound: "Pop", interruptionLevel: "active", relevanceScore: 0.5, dismissAfter: 8 },
  2: { sound: "Tink", interruptionLevel: "active", relevanceScore: 0.25, dismissAfter: 5 },
  1: { sound: "Tink", interruptionLevel: "active", relevanceScore: 0.0, dismissAfter: 4 },
}

/** Resolve the effective priority config, applying user overrides for sounds and dismiss timing. */
export function resolvePriorityConfig(
  priority: number,
  soundOverrides?: SoundConfig,
  dismissOverrides?: DismissConfig,
): PriorityConfig {
  const base = PRIORITY_CONFIG[priority] ?? PRIORITY_CONFIG[3]
  const soundOverride = soundOverrides?.[String(priority)]
  const dismissOverride = dismissOverrides?.[String(priority)]
  if (soundOverride === undefined && dismissOverride === undefined) return base
  return {
    ...base,
    ...(soundOverride !== undefined ? { sound: soundOverride as SystemSound | null } : {}),
    ...(dismissOverride !== undefined ? { dismissAfter: dismissOverride } : {}),
  }
}

export function getSound(priority?: number, soundOverrides?: SoundConfig): SystemSound | null {
  return resolvePriorityConfig(priority ?? 3, soundOverrides).sound
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

// ─── Default actions ─────────────────────────────────────────────────────────

const ACTION_LABELS: Record<string, Record<string, string>> = {
  acknowledge: {
    en: "Acknowledge",
    de: "Bestätigen",
    fr: "Confirmer",
    es: "Confirmar",
    ja: "確認",
    zh: "确认",
  },
  "remind-5m": {
    en: "Remind in 5 min",
    de: "In 5 Min erinnern",
    fr: "Rappel dans 5 min",
    es: "Recordar en 5 min",
    ja: "5分後に通知",
    zh: "5分钟后提醒",
  },
  "remind-30m": {
    en: "Remind in 30 min",
    de: "In 30 Min erinnern",
    fr: "Rappel dans 30 min",
    es: "Recordar en 30 min",
    ja: "30分後に通知",
    zh: "30分钟后提醒",
  },
  "remind-tomorrow": {
    en: "Remind tomorrow morning",
    de: "Morgen früh erinnern",
    fr: "Rappel demain matin",
    es: "Recordar mañana por la mañana",
    ja: "明日の朝に通知",
    zh: "明早提醒",
  },
}

function getSystemLanguage(): string {
  try {
    const result = Bun.spawnSync(["defaults", "read", "-g", "AppleLanguages"])
    const output = result.stdout.toString()
    const match = output.match(/"?([a-z]{2})-/i)
    if (match) return match[1].toLowerCase()
  } catch {}
  return "en"
}

function localizedLabel(id: string): string {
  const lang = getSystemLanguage()
  return ACTION_LABELS[id]?.[lang] ?? ACTION_LABELS[id]?.en ?? id
}

/** Default action buttons shown when a notification has no custom actions. */
export const DEFAULT_ACTIONS: NotificationAction[] = [
  { identifier: "acknowledge", title: localizedLabel("acknowledge") },
  { identifier: "remind-5m", title: localizedLabel("remind-5m") },
  { identifier: "remind-30m", title: localizedLabel("remind-30m") },
  { identifier: "remind-tomorrow", title: localizedLabel("remind-tomorrow") },
]

export const DEFAULT_CATEGORY_ID = "ntfy-default-actions"

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
  dismissAfter?: number
  clickUrl?: string
  imageUrl?: string
  actions?: NotificationAction[]
  categoryId?: string
}

export function buildNtfyPayload(
  msg: NtfyMessage,
  soundOverrides?: SoundConfig,
  dismissOverrides?: DismissConfig,
): NtfyNotificationPayload {
  const title = msg.title ?? capitalize(msg.topic)
  const tags = renderTags(msg.tags)
  const subtitle = tags ? `${msg.topic} • ${tags}` : msg.topic
  const { sound, interruptionLevel, relevanceScore, dismissAfter } = resolvePriorityConfig(
    msg.priority ?? 3,
    soundOverrides,
    dismissOverrides,
  )

  const payload: NtfyNotificationPayload = {
    title,
    subtitle,
    body: msg.message,
    sound,
    threadId: msg.topic,
    interruptionLevel,
    relevanceScore,
    ...(dismissAfter > 0 ? { dismissAfter } : {}),
  }

  if (msg.click) payload.clickUrl = msg.click

  const imageUrl = selectImageUrl(msg)
  if (imageUrl) payload.imageUrl = imageUrl

  const actions = mapActions(msg)
  if (actions.length > 0) {
    payload.actions = actions
    payload.categoryId = `ntfy-${msg.id.slice(0, 8)}`
  } else {
    payload.actions = DEFAULT_ACTIONS
    payload.categoryId = DEFAULT_CATEGORY_ID
  }

  return payload
}

// ─── Notification senders ─────────────────────────────────────────────────────

export async function sendNotification(
  msg: NtfyMessage,
  soundOverrides?: SoundConfig,
  dismissOverrides?: DismissConfig,
): Promise<void> {
  const payload = buildNtfyPayload(msg, soundOverrides, dismissOverrides)
  const prio = msg.priority ?? 3
  console.log(`notify: [${msg.topic}] p${prio} ${payload.title}`)
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
