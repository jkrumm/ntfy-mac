import { join } from "path"
import { readdirSync, unlinkSync } from "fs"
import { STATE_DIR } from "./state"
import { NotificationBuilder } from "./notifications"
import type { NotificationQueue } from "./queue"
import type { StateAccessor } from "./ntfy"
import type { PendingReminder } from "./types"

const REMINDER_PREFIX = "reminder-"
const POLL_INTERVAL_MS = 10_000

let isTickRunning = false

/**
 * Scans for reminder-*.json files written by the Swift helper,
 * merges them into persistent state, and fires any that are due
 * by enqueuing them through the notification queue.
 * Runs every 10s in the daemon.
 */
export function startReminderPoll(queue: NotificationQueue, state: StateAccessor): void {
  // Run immediately on startup to catch reminders missed during downtime
  tick(queue, state).catch((err) => console.error("reminders: poll error:", err))
  setInterval(() => {
    // Prevent overlapping tick() calls if previous one is still running
    if (!isTickRunning) {
      tick(queue, state).catch((err) => console.error("reminders: poll error:", err))
    }
  }, POLL_INTERVAL_MS)
}

async function tick(queue: NotificationQueue, stateAccessor: StateAccessor): Promise<void> {
  if (isTickRunning) return
  isTickRunning = true

  try {
    let reminders = (stateAccessor.get().reminders ?? []).filter(isValidReminder)
    let changed = reminders.length !== (stateAccessor.get().reminders ?? []).length

    // 1. Ingest new reminder files from the Swift helper
    try {
      const files = readdirSync(STATE_DIR).filter(
        (f) => f.startsWith(REMINDER_PREFIX) && f.endsWith(".json"),
      )
      for (const file of files) {
        const path = join(STATE_DIR, file)
        try {
          const raw = await Bun.file(path).text()
          const reminder = JSON.parse(raw)
          if (isValidReminder(reminder)) {
            reminders.push(reminder)
            changed = true
          }
        } catch (err) {
          // Log read/parse errors but skip malformed files
          if (err instanceof Error && err.message.includes("ENOENT")) {
            // File was deleted between readdir and read — OK
          } else {
            console.error(`reminders: failed to parse ${file}:`, err)
          }
        }
        try {
          unlinkSync(path)
        } catch (err) {
          // Only log if it's not ENOENT (file already deleted)
          if (err && typeof err === "object" && "code" in err && err.code !== "ENOENT") {
            console.error(`reminders: failed to delete ${file}:`, err)
          }
        }
      }
    } catch (err) {
      // STATE_DIR doesn't exist yet — nothing to ingest
      if (err && typeof err === "object" && "code" in err && err.code !== "ENOENT") {
        console.error("reminders: failed to scan state dir:", err)
      }
    }

    // 2. Fire any reminders that are due — enqueue through the notification queue
    const now = Date.now()
    const due = reminders.filter((r) => r.fireAt <= now)
    const pending = reminders.filter((r) => r.fireAt > now)

    for (const reminder of due) {
      const payload = buildReminderPayload(reminder)
      console.log(`reminders: firing "${reminder.title}"`)
      queue.enqueue({
        id: `reminder-${reminder.id}`,
        payload,
        priority: 3,
        source: "reminder",
        maxAttempts: 1,
      })
      changed = true
    }

    // 3. Persist if anything changed
    if (changed) {
      stateAccessor.update((s) => ({
        ...s,
        reminders: pending.length > 0 ? pending : undefined,
      }))
    }
  } finally {
    isTickRunning = false
  }
}

function isValidReminder(obj: unknown): obj is PendingReminder {
  if (!obj || typeof obj !== "object") return false
  const r = obj as Record<string, unknown>
  return (
    typeof r.id === "string" &&
    typeof r.fireAt === "number" &&
    typeof r.title === "string" &&
    typeof r.body === "string" &&
    r.fireAt > 0 &&
    r.id.length > 0
  )
}

function buildReminderPayload(reminder: PendingReminder) {
  const builder = new NotificationBuilder(`🔁 ${reminder.title}`, reminder.body)
    .sound("Pop")
    .interruptionLevel("active")

  if (reminder.subtitle) builder.subtitle(`reminder • ${reminder.subtitle}`)
  if (reminder.threadId) builder.thread(reminder.threadId)
  if (reminder.clickUrl) builder.clickUrl(reminder.clickUrl)

  return builder.build()
}
