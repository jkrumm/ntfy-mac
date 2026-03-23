import { describe, expect, it } from "bun:test"
import { NotificationQueue, type EnqueueInput, type SendFn } from "../src/queue"
import type { NotificationPayload } from "../src/notifications"

// ─── Test helpers ────────────────────────────────────────────────────────────

function makePayload(title: string): NotificationPayload {
  return { title, body: "test body" }
}

function makeInput(overrides: Partial<EnqueueInput> & { id: string }): EnqueueInput {
  return {
    payload: makePayload(overrides.id),
    priority: 3,
    source: "sse",
    maxAttempts: 3,
    ...overrides,
  }
}

interface SendRecord {
  payload: NotificationPayload
  timestamp: number
}

function createTestSend(result: boolean = true) {
  const calls: SendRecord[] = []
  const send: SendFn = async (payload) => {
    calls.push({ payload, timestamp: Date.now() })
    return result
  }
  return { send, calls }
}

/** Wait for the queue to fully drain. */
async function waitDrain(queue: NotificationQueue, timeoutMs = 5000): Promise<void> {
  const start = Date.now()
  while (queue.pending > 0) {
    if (Date.now() - start > timeoutMs) throw new Error("queue drain timeout")
    await Bun.sleep(10)
  }
  // One more tick to let the final send complete
  await Bun.sleep(50)
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe("NotificationQueue", () => {
  it("sends a single notification", async () => {
    const { send, calls } = createTestSend()
    const queue = new NotificationQueue(send, 0)

    queue.enqueue(makeInput({ id: "msg-1" }))
    await waitDrain(queue)

    expect(calls).toHaveLength(1)
    expect(calls[0].payload.title).toBe("msg-1")
    queue.destroy()
  })

  it("drains in priority order (higher priority first)", async () => {
    const { send, calls } = createTestSend()
    const queue = new NotificationQueue(send, 0)

    // Enqueue in mixed order
    queue.enqueue(makeInput({ id: "p1", priority: 1 }))
    queue.enqueue(makeInput({ id: "p5", priority: 5 }))
    queue.enqueue(makeInput({ id: "p3", priority: 3 }))

    await waitDrain(queue)

    expect(calls.map((c) => c.payload.title)).toEqual(["p5", "p3", "p1"])
    queue.destroy()
  })

  it("FIFO within the same priority", async () => {
    const { send, calls } = createTestSend()
    const queue = new NotificationQueue(send, 0)

    queue.enqueue(makeInput({ id: "first", priority: 3 }))
    queue.enqueue(makeInput({ id: "second", priority: 3 }))
    queue.enqueue(makeInput({ id: "third", priority: 3 }))

    await waitDrain(queue)

    expect(calls.map((c) => c.payload.title)).toEqual(["first", "second", "third"])
    queue.destroy()
  })

  it("enforces minimum interval between sends", async () => {
    const { send, calls } = createTestSend()
    const intervalMs = 100
    const queue = new NotificationQueue(send, intervalMs)

    queue.enqueue(makeInput({ id: "a" }))
    queue.enqueue(makeInput({ id: "b" }))
    queue.enqueue(makeInput({ id: "c" }))

    await waitDrain(queue)

    expect(calls).toHaveLength(3)

    // Gap between consecutive sends should be >= intervalMs (with small tolerance)
    const gap1 = calls[1].timestamp - calls[0].timestamp
    const gap2 = calls[2].timestamp - calls[1].timestamp
    expect(gap1).toBeGreaterThanOrEqual(intervalMs - 15)
    expect(gap2).toBeGreaterThanOrEqual(intervalMs - 15)
    queue.destroy()
  })

  it("first send is immediate (no initial pacing delay)", async () => {
    const { send, calls } = createTestSend()
    const queue = new NotificationQueue(send, 1000) // long interval

    const before = Date.now()
    queue.enqueue(makeInput({ id: "immediate" }))

    // Wait for just the first send, not full drain
    await Bun.sleep(100)

    expect(calls).toHaveLength(1)
    const delay = calls[0].timestamp - before
    expect(delay).toBeLessThan(100)
    queue.destroy()
  })

  it("retries on failure up to maxAttempts", async () => {
    let callCount = 0
    const send: SendFn = async () => {
      callCount++
      return callCount >= 3 // succeeds on 3rd attempt
    }
    const queue = new NotificationQueue(send, 0)

    queue.enqueue(makeInput({ id: "retry-me", maxAttempts: 3 }))
    await waitDrain(queue)

    expect(callCount).toBe(3)
    queue.destroy()
  })

  it("drops item after maxAttempts exhausted", async () => {
    const send: SendFn = async () => false // always fails
    const queue = new NotificationQueue(send, 0)

    queue.enqueue(makeInput({ id: "doomed", maxAttempts: 2 }))
    await waitDrain(queue)

    expect(queue.pending).toBe(0)
    queue.destroy()
  })

  it("system notifications (maxAttempts: 1) are not retried", async () => {
    let callCount = 0
    const send: SendFn = async () => {
      callCount++
      return false
    }
    const queue = new NotificationQueue(send, 0)

    queue.enqueue(makeInput({ id: "system", source: "system", maxAttempts: 1 }))
    await waitDrain(queue)

    expect(callCount).toBe(1)
    queue.destroy()
  })

  it("handles send throwing an exception", async () => {
    let callCount = 0
    const send: SendFn = async () => {
      callCount++
      if (callCount === 1) throw new Error("spawn failed")
      return true
    }
    const queue = new NotificationQueue(send, 0)

    queue.enqueue(makeInput({ id: "crash", maxAttempts: 3 }))
    await waitDrain(queue)

    expect(callCount).toBe(2) // first threw, second succeeded
    queue.destroy()
  })

  it("enqueue during drain picks up new item", async () => {
    const { send, calls } = createTestSend()
    const queue = new NotificationQueue(send, 0)

    queue.enqueue(makeInput({ id: "first" }))

    // Wait for first to start processing
    await Bun.sleep(20)

    // Enqueue while drain is running
    queue.enqueue(makeInput({ id: "second" }))

    await waitDrain(queue)

    expect(calls.map((c) => c.payload.title)).toContain("first")
    expect(calls.map((c) => c.payload.title)).toContain("second")
    queue.destroy()
  })

  it("empty queue: drain exits cleanly", async () => {
    const { send, calls } = createTestSend()
    const queue = new NotificationQueue(send, 0)

    // Never enqueue anything, just verify no errors
    await Bun.sleep(50)

    expect(calls).toHaveLength(0)
    expect(queue.pending).toBe(0)
    queue.destroy()
  })

  it("destroy() stops the drain timer", async () => {
    const { send, calls } = createTestSend()
    const queue = new NotificationQueue(send, 200)

    queue.enqueue(makeInput({ id: "a" }))
    queue.enqueue(makeInput({ id: "b" }))

    // Wait for first send
    await Bun.sleep(50)
    expect(calls).toHaveLength(1)

    queue.destroy()

    // Wait past the interval — second should NOT be sent
    await Bun.sleep(300)
    expect(calls).toHaveLength(1)
  })

  it("high-priority item enqueued later still drains before lower priority", async () => {
    const order: string[] = []
    const send: SendFn = async (payload) => {
      order.push(payload.title)
      // Simulate some processing time so second enqueue lands during drain
      await Bun.sleep(10)
      return true
    }
    const queue = new NotificationQueue(send, 0)

    queue.enqueue(makeInput({ id: "low", priority: 1 }))
    queue.enqueue(makeInput({ id: "mid", priority: 3 }))

    // Give drain a moment to start (it'll process "mid" first since priority 3 > 1)
    await Bun.sleep(5)

    // Now add a high priority item — it should jump ahead of remaining low
    queue.enqueue(makeInput({ id: "high", priority: 5 }))

    await waitDrain(queue)

    // "mid" was already being processed, then "high" jumps ahead of "low"
    expect(order[0]).toBe("mid")
    expect(order[1]).toBe("high")
    expect(order[2]).toBe("low")
    queue.destroy()
  })
})
