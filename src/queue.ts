import type { NotificationPayload } from "./notifications"

// ─── Types ───────────────────────────────────────────────────────────────────

export type NotificationSource = "sse" | "poll" | "reminder" | "system"

export interface QueueItem {
  id: string
  payload: NotificationPayload
  priority: number // 1-5, higher drains first
  source: NotificationSource
  maxAttempts: number // 3 for ntfy messages, 1 for system/reminder
  enqueuedAt: number
  attempts: number
}

export type EnqueueInput = Omit<QueueItem, "enqueuedAt" | "attempts">

/**
 * Send function injected into the queue. Returns true if delivery succeeded.
 * The queue retries on false, up to item.maxAttempts.
 */
export type SendFn = (payload: NotificationPayload) => Promise<boolean>

// ─── Queue ───────────────────────────────────────────────────────────────────

const DEFAULT_MIN_INTERVAL_MS = 1500

/**
 * In-memory priority queue for macOS notification delivery.
 *
 * Paces sends to avoid macOS banner rate-limiting. Higher priority items
 * drain first. Failed sends are retried up to maxAttempts.
 *
 * Not persisted — on daemon restart, SSE replay rebuilds the queue naturally.
 */
export class NotificationQueue {
  private items: QueueItem[] = []
  private draining = false
  private destroyed = false
  private timer: ReturnType<typeof setTimeout> | null = null
  private lastSendAt = 0

  constructor(
    private readonly send: SendFn,
    private readonly minIntervalMs = DEFAULT_MIN_INTERVAL_MS,
  ) {}

  /**
   * Add a notification to the queue. Sorted by priority (desc), then arrival (asc).
   * Kicks the drain loop if not already running.
   */
  enqueue(input: EnqueueInput): void {
    if (this.destroyed) return
    const item: QueueItem = { ...input, enqueuedAt: Date.now(), attempts: 0 }
    this.insertSorted(item)
    this.scheduleDrain()
  }

  /** Number of items waiting to be sent. */
  get pending(): number {
    return this.items.length
  }

  /** Stop the drain loop. Call on SIGTERM/SIGINT. */
  destroy(): void {
    this.destroyed = true
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }

  // ─── Internals ─────────────────────────────────────────────────────────

  private insertSorted(item: QueueItem): void {
    // Binary search for insertion point: priority desc, then enqueuedAt asc
    let lo = 0
    let hi = this.items.length
    while (lo < hi) {
      const mid = (lo + hi) >>> 1
      const existing = this.items[mid]
      if (
        existing.priority > item.priority ||
        (existing.priority === item.priority && existing.enqueuedAt <= item.enqueuedAt)
      ) {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    this.items.splice(lo, 0, item)
  }

  private scheduleDrain(): void {
    if (this.destroyed || this.draining || this.timer) return
    const elapsed = Date.now() - this.lastSendAt
    const wait = Math.max(0, this.minIntervalMs - elapsed)
    // First send is immediate (lastSendAt starts at 0)
    this.timer = setTimeout(() => {
      this.timer = null
      this.drain()
    }, wait)
  }

  private async drain(): Promise<void> {
    if (this.draining) return
    this.draining = true

    try {
      while (this.items.length > 0 && !this.destroyed) {
        // Enforce pacing
        const elapsed = Date.now() - this.lastSendAt
        const wait = this.minIntervalMs - elapsed
        if (wait > 0 && this.lastSendAt > 0) {
          await Bun.sleep(wait)
          if (this.destroyed) break
        }

        const item = this.items.shift()!
        item.attempts++

        try {
          const ok = await this.send(item.payload)

          if (!ok && item.attempts < item.maxAttempts) {
            console.log(
              `queue: delivery failed for "${item.payload.title}", retry ${item.attempts}/${item.maxAttempts}`,
            )
            this.insertSorted(item)
          } else if (!ok) {
            console.error(
              `queue: delivery failed for "${item.payload.title}" after ${item.attempts} attempts, dropping`,
            )
          }
        } catch (err) {
          if (item.attempts < item.maxAttempts) {
            console.log(
              `queue: send error for "${item.payload.title}", retry ${item.attempts}/${item.maxAttempts}`,
            )
            this.insertSorted(item)
          } else {
            console.error(
              `queue: send error for "${item.payload.title}" after ${item.attempts} attempts:`,
              err,
            )
          }
        }

        this.lastSendAt = Date.now()
      }
    } finally {
      this.draining = false
    }
  }
}
