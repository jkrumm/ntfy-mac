/**
 * TypeSafe adapter for macOS UserNotifications via the ntfy-notify Swift helper.
 *
 * Architecture:
 *   TypeScript → JSON (stdin) → ntfy-notify.app (Swift) → UNUserNotificationCenter
 *
 * The Swift helper is a minimal NSApplication that accepts a JSON payload on stdin,
 * posts the notification via UNUserNotificationCenter, and exits. It must be a proper
 * .app bundle (with CFBundleIdentifier in Info.plist) for the OS to attribute
 * notifications to ntfy-mac and persist permission state across runs.
 */

import { homedir } from "os"
import { join } from "path"
import { detectInstallMethod } from "./updater"

// ─── Types ────────────────────────────────────────────────────────────────────

/**
 * macOS system sound names. All are available without additional installation.
 * Volumes and styles differ — use to convey urgency alongside `interruptionLevel`.
 *
 * Urgency guidance:
 *   High (5): Sosumi — jarring, use for critical failures
 *   Mid (4):  Ping   — crisp, use for important events
 *   Default:  Pop    — subtle, use for normal ntfy messages
 *   Low:      null   — silent banner
 */
export type SystemSound =
  | "Basso"
  | "Blow"
  | "Bottle"
  | "Frog"
  | "Funk"
  | "Glass"
  | "Hero"
  | "Morse"
  | "Ping"
  | "Pop"
  | "Purr"
  | "Sosumi"
  | "Submarine"
  | "Tink"

/**
 * Maps to UNNotificationInterruptionLevel (macOS 12+).
 *
 * - passive:        Silently added to Notification Center, no banner or sound.
 * - active:         Banner + sound. Default behavior.
 * - time-sensitive: Breaks through Focus filters (Work, Sleep, etc).
 *                   Requires NSUserNotificationAlertStyle = alert in Info.plist.
 *                   No special entitlement needed for local notifications.
 */
export type InterruptionLevel = "passive" | "active" | "time-sensitive"

/**
 * An action button shown on the notification. Stored in userInfo and restored
 * on re-launch so the Swift helper can handle the interaction without state files.
 */
export interface NotificationAction {
  /** Unique key that matches a registered UNNotificationAction identifier. */
  identifier: string
  title: string
  /** view action: URL to open in the default browser. */
  url?: string
  /** http action: URL to fire a request against. */
  httpUrl?: string
  httpMethod?: string
  httpHeaders?: Record<string, string>
  httpBody?: string
  destructive?: boolean
}

/**
 * The full notification payload — mirrors the Swift Payload struct field-for-field.
 * All optional fields fall back to system defaults when omitted.
 */
export interface NotificationPayload {
  /** Primary line — bold. Shown in both banner and Notification Center. */
  title: string
  /** Secondary line — shown below title. Use for context (topic, tags). */
  subtitle?: string
  /** Main content body. Truncated in banners; fully visible in NC. */
  body: string
  /**
   * System sound to play. Pass null to deliver silently (no sound at all).
   * When omitted, the system default sound plays.
   */
  sound?: SystemSound | null
  /**
   * Notification Center thread grouping key.
   * All notifications with the same threadId collapse into a group in NC.
   * Use the ntfy topic name so messages from the same topic stack together.
   */
  threadId?: string
  /**
   * Controls banner behavior and Focus mode interaction. Defaults to "active".
   * "passive" is useful for low-priority informational notifications.
   * "time-sensitive" cuts through Do Not Disturb / Focus filters.
   */
  interruptionLevel?: InterruptionLevel
  /**
   * Sort score within a thread group in Notification Center.
   * Range: 0.0 (lowest) – 1.0 (highest). Higher = shown first in the group.
   * Omit to use the system default (chronological order).
   */
  relevanceScore?: number
  /**
   * URL to open when the user clicks the notification body.
   * Stored in userInfo — opened by the Swift helper on re-launch after interaction,
   * not immediately on delivery.
   */
  clickUrl?: string
  /**
   * Remote image URL. The Swift helper downloads it synchronously and attaches it
   * as a UNNotificationAttachment (inline image in the notification).
   */
  imageUrl?: string
  /**
   * Action buttons to register with UNNotificationCategory and display on the notification.
   * Up to 3 buttons are shown on macOS. Stored in userInfo for re-launch handling.
   */
  actions?: NotificationAction[]
  /**
   * Category identifier linking the notification to its registered UNNotificationCategory.
   * Required when actions are present. Auto-generated from message id if omitted.
   */
  categoryId?: string
}

// ─── Helper path resolution ───────────────────────────────────────────────────

/**
 * Resolves the ntfy-notify helper binary path based on install method.
 *
 * Homebrew:  .../Cellar/ntfy-mac/VERSION/libexec/ntfy-notify.app/...
 * curl:      ~/.local/share/ntfy-mac/ntfy-notify.app/...
 * dev:       ~/Applications/ntfy-notify.app/... (must be built + copied once via build-helper.sh)
 */
export function resolveHelperPath(): string {
  const method = detectInstallMethod()

  if (method === "brew") {
    // process.execPath = .../Cellar/ntfy-mac/VERSION/bin/ntfy-mac
    const cellarPrefix = join(process.execPath, "..", "..")
    return join(cellarPrefix, "libexec", "ntfy-notify.app", "Contents", "MacOS", "ntfy-notify")
  }

  if (method === "curl") {
    return join(
      homedir(),
      ".local",
      "share",
      "ntfy-mac",
      "ntfy-notify.app",
      "Contents",
      "MacOS",
      "ntfy-notify",
    )
  }

  // dev: use ~/Applications so Launch Services registers the icon correctly.
  // Run `bun run build:helper` then `cp -R assets/ntfy-notify.app ~/Applications/` once.
  return join(homedir(), "Applications", "ntfy-notify.app", "Contents", "MacOS", "ntfy-notify")
}

// ─── Core send ────────────────────────────────────────────────────────────────

const DEBUG = process.env.NTFY_DEBUG === "1"

/**
 * Sends a notification via the ntfy-notify Swift helper.
 *
 * The payload is serialized to JSON and written to the helper's stdin.
 * Errors are logged (with NTFY_DEBUG=1) but never thrown — notification
 * delivery is best-effort and should not crash the daemon.
 */
export async function sendNotificationPayload(payload: NotificationPayload): Promise<void> {
  const helperPath = resolveHelperPath()

  // Strip undefined/null values (Swift Decodable treats missing keys as nil)
  const json = JSON.stringify(payload, (_key, value) => (value === undefined ? undefined : value))

  if (DEBUG) {
    console.log(`[debug] notify helper: ${helperPath}`)
    console.log(`[debug] notify payload: ${json}`)
  }

  try {
    const proc = Bun.spawn([helperPath], {
      stdin: Buffer.from(json),
      stdout: "ignore",
      stderr: DEBUG ? "inherit" : "ignore",
    })
    await proc.exited
    if (DEBUG && proc.exitCode !== 0) {
      console.error(`[debug] notify: helper exited ${proc.exitCode}`)
    }
  } catch (err) {
    if (DEBUG) console.error("[debug] notify: spawn failed:", err)
  }
}

// ─── Payload builder ──────────────────────────────────────────────────────────

/**
 * Fluent, immutable builder for NotificationPayload.
 * Produces a plain object — pass to sendNotificationPayload() to deliver.
 *
 * @example
 * await sendNotificationPayload(
 *   new NotificationBuilder("ntfy-mac", "Connection lost")
 *     .sound("Sosumi")
 *     .interruptionLevel("time-sensitive")
 *     .build()
 * )
 */
export class NotificationBuilder {
  private readonly _payload: NotificationPayload

  constructor(title: string, body: string) {
    this._payload = { title, body }
  }

  subtitle(text: string): this {
    ;(this._payload as { subtitle?: string }).subtitle = text
    return this
  }

  /** Pass null for a silent (no sound) notification. */
  sound(name: SystemSound | null): this {
    ;(this._payload as { sound?: SystemSound | null }).sound = name
    return this
  }

  /**
   * Groups this notification with others sharing the same threadId in NC.
   * Use the ntfy topic name to stack topic messages together.
   */
  thread(id: string): this {
    ;(this._payload as { threadId?: string }).threadId = id
    return this
  }

  interruptionLevel(level: InterruptionLevel): this {
    ;(this._payload as { interruptionLevel?: InterruptionLevel }).interruptionLevel = level
    return this
  }

  /** 0.0–1.0 sort score within a thread. Higher = shown first. */
  relevanceScore(score: number): this {
    ;(this._payload as { relevanceScore?: number }).relevanceScore = Math.max(0, Math.min(1, score))
    return this
  }

  /** URL to open when the user clicks the notification body (not on delivery). */
  clickUrl(url: string): this {
    ;(this._payload as { clickUrl?: string }).clickUrl = url
    return this
  }

  /** Remote image URL — downloaded by the Swift helper and shown inline. */
  imageUrl(url: string): this {
    ;(this._payload as { imageUrl?: string }).imageUrl = url
    return this
  }

  /** Action buttons (view/http). Pass categoryId linking to the registered category. */
  actions(items: NotificationAction[], categoryId: string): this {
    ;(this._payload as { actions?: NotificationAction[] }).actions = items
    ;(this._payload as { categoryId?: string }).categoryId = categoryId
    return this
  }

  build(): NotificationPayload {
    return { ...this._payload }
  }

  /** Convenience: build and send in one call. */
  send(): Promise<void> {
    return sendNotificationPayload(this.build())
  }
}
