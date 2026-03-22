import { homedir } from "os"
import { join } from "path"
import { readdirSync, unlinkSync } from "fs"
import { loadState, saveState } from "./dedup"
import { NotificationBuilder } from "./notifications"
import type { PendingReminder } from "./types"

const STATE_DIR = `${homedir()}/.local/share/ntfy-mac`
const REMINDER_PREFIX = "reminder-"
const POLL_INTERVAL_MS = 10_000

let isTickRunning = false

/**
 * Scans for reminder-*.json files written by the Swift helper,
 * merges them into persistent state, and fires any that are due.
 * Runs every 10s in the daemon.
 */
export function startReminderPoll(): void {
  // Run immediately on startup to catch reminders missed during downtime
  tick().catch((err) => console.error("reminders: poll error:", err))
  setInterval(() => {
    // Prevent overlapping tick() calls if previous one is still running
    if (!isTickRunning) {
      tick().catch((err) => console.error("reminders: poll error:", err))
    }
  }, POLL_INTERVAL_MS)
}

async function tick(): Promise<void> {
  if (isTickRunning) return
  isTickRunning = true

  try {
    const state = await loadState()
    let reminders = (state.reminders ?? []).filter(isValidReminder)
    let changed = reminders.length !== (state.reminders ?? []).length

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

    // 2. Fire any reminders that are due
    const now = Date.now()
    const due = reminders.filter((r) => r.fireAt <= now)
    const pending = reminders.filter((r) => r.fireAt > now)

    for (const reminder of due) {
      await fireReminder(reminder)
      changed = true
    }

    // 3. Persist if anything changed
    if (changed) {
      await saveState({ ...state, reminders: pending.length > 0 ? pending : undefined })
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

async function fireReminder(reminder: PendingReminder): Promise<void> {
  const builder = new NotificationBuilder(`🔁 ${reminder.title}`, reminder.body)
    .sound("Pop")
    .interruptionLevel("active")

  if (reminder.subtitle) builder.subtitle(`reminder • ${reminder.subtitle}`)
  if (reminder.threadId) builder.thread(reminder.threadId)
  if (reminder.clickUrl) builder.clickUrl(reminder.clickUrl)

  console.log(`reminders: firing "${reminder.title}"`)
  await builder.send()
}
