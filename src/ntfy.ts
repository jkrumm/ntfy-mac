import type { Config, NtfyMessage } from "./types"
import { loadState, saveState, markSeen } from "./dedup"

const DEBUG = process.env.NTFY_DEBUG === "1"
function debug(...args: unknown[]): void {
  if (DEBUG) console.log("[debug]", ...args)
}

// Missed-message categorization thresholds
const INDIVIDUAL_THRESHOLD_MS = 1 * 60 * 60 * 1000 // < 1h → show individually
const SILENT_THRESHOLD_MS = 12 * 60 * 60 * 1000 // > 12h → silent

// Exponential backoff config
const BACKOFF_INITIAL_MS = 5_000
const BACKOFF_MAX_MS = 5 * 60 * 1000

// Alert user after this many consecutive SSE failures (~40min at max backoff)
const FAILURE_ALERT_THRESHOLD = 12

// Keepalive timeout: ntfy sends keepalives every ~55s. If we see nothing for
// 90s the connection has silently stalled — abort and reconnect.
const KEEPALIVE_TIMEOUT_MS = 90_000

export type MissedMessageResult =
  | { type: "individual"; messages: NtfyMessage[] }
  | { type: "summary"; count: number; oldestTopic: string }
  | { type: "silent" }

interface AccountResponse {
  subscriptions?: { topic: string }[]
}

export async function discoverTopics(config: Config): Promise<string[]> {
  const res = await fetch(`${config.url}/v1/account`, {
    headers: { Authorization: `Bearer ${config.token}` },
  })
  if (res.status === 401) throw new Error("ntfy auth failed (401) — run ntfy-mac setup")
  if (!res.ok) throw new Error(`ntfy /v1/account returned ${res.status}`)
  const body = (await res.json()) as AccountResponse
  return (body.subscriptions ?? []).map((s) => s.topic)
}

export function parseNtfyLine(line: string): NtfyMessage | null {
  if (!line.trim()) return null
  try {
    const parsed = JSON.parse(line) as NtfyMessage
    if (!parsed.id || !parsed.topic || !parsed.message) return null
    return parsed
  } catch {
    return null
  }
}

export function categorizeMissedMessages(messages: NtfyMessage[]): MissedMessageResult {
  if (messages.length === 0) return { type: "silent" }

  const now = Date.now()
  const oldestTime = Math.min(...messages.map((m) => m.time * 1000))
  const age = now - oldestTime

  if (age > SILENT_THRESHOLD_MS) return { type: "silent" }

  if (age > INDIVIDUAL_THRESHOLD_MS) {
    const oldestTopic = messages.reduce((a, b) => (a.time < b.time ? a : b)).topic
    return { type: "summary", count: messages.length, oldestTopic }
  }

  return { type: "individual", messages }
}

export async function pollMessages(
  config: Config,
  topics: string[],
  since: string,
): Promise<NtfyMessage[]> {
  const url = `${config.url}/${topics.join(",")}/json?since=${since}&poll=1`
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${config.token}` },
  })
  if (!res.ok) throw new Error(`ntfy poll returned ${res.status}`)
  const text = await res.text()
  return text
    .split("\n")
    .map(parseNtfyLine)
    .filter((m): m is NtfyMessage => m !== null)
}

// Wraps reader.read() with a keepalive timeout. Throws if no data arrives
// within KEEPALIVE_TIMEOUT_MS — signals a silently stalled connection.
async function readWithTimeout(
  reader: ReadableStreamDefaultReader<Uint8Array>,
): Promise<{ done: boolean; value?: Uint8Array }> {
  const timeout = new Promise<never>((_, reject) =>
    setTimeout(
      () => reject(new Error("SSE keepalive timeout — connection stalled")),
      KEEPALIVE_TIMEOUT_MS,
    ),
  )
  return Promise.race([reader.read(), timeout])
}

async function connectSSE(
  config: Config,
  topics: string[],
  since: string,
  onMessage: (msg: NtfyMessage) => Promise<void>,
): Promise<void> {
  const url = `${config.url}/${topics.join(",")}/sse?since=${since}`
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${config.token}`,
      Accept: "text/event-stream",
    },
  })
  if (!res.ok) throw new Error(`ntfy SSE returned ${res.status}`)
  if (!res.body) throw new Error("ntfy SSE response has no body")

  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ""

  try {
    while (true) {
      const { done, value } = await readWithTimeout(reader)
      if (done) break
      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split("\n")
      buffer = lines.pop() ?? ""
      for (const line of lines) {
        // Track keepalives and messages equally for heartbeat purposes
        if (line.startsWith("event: keepalive")) {
          debug("keepalive received")
        }
        if (!line.startsWith("data: ")) continue
        const msg = parseNtfyLine(line.slice(6))
        if (msg) {
          debug(`received ${msg.topic}/${msg.id} priority=${msg.priority ?? "default"}`)
          await onMessage(msg)
        }
      }
    }
  } finally {
    reader.cancel().catch(() => {})
  }
}

export async function startListener(
  config: Config,
  topics: string[],
  onMessage: (msg: NtfyMessage) => Promise<void>,
  onMissed: (result: MissedMessageResult) => Promise<void>,
  onConnectionFailure?: () => Promise<void>,
): Promise<never> {
  let backoff = BACKOFF_INITIAL_MS
  let consecutiveFailures = 0
  let state = await loadState()
  let since = state.lastMessageId ?? "latest"

  while (true) {
    try {
      console.log(
        `connected (topics: ${topics.length}, since: ${since === "latest" ? "now" : since.slice(0, 8)})`,
      )
      await connectSSE(config, topics, since, async (msg) => {
        state = await loadState()
        state = { ...state, lastMessageId: msg.id }
        await saveState(state)
        since = msg.id
        backoff = BACKOFF_INITIAL_MS
        consecutiveFailures = 0
        await onMessage(msg)
      })
      console.log("connection closed — reconnecting")
    } catch (err) {
      consecutiveFailures++
      const message = err instanceof Error ? err.message : String(err)
      console.error(`connection error (attempt ${consecutiveFailures}): ${message}`)

      // Alert user after sustained failure (~40min)
      if (consecutiveFailures === FAILURE_ALERT_THRESHOLD && onConnectionFailure) {
        await onConnectionFailure().catch(() => {})
      }
    }

    // Poll for any messages missed during the gap
    try {
      if (since !== "latest") {
        debug(`polling for missed messages since=${since}`)
        const missed = await pollMessages(config, topics, since)
        const unseen = missed.filter((m) => !state.seen[m.id])
        if (unseen.length > 0) {
          console.log(`poll: ${unseen.length} missed message(s)`)
          await onMissed(categorizeMissedMessages(unseen))
          for (const m of unseen) {
            state = markSeen(state, m.id)
            state = { ...state, lastMessageId: m.id }
            since = m.id
          }
          await saveState(state)
        }
      }
    } catch (pollErr) {
      console.error("poll error:", pollErr instanceof Error ? pollErr.message : pollErr)
    }

    console.log(`reconnecting in ${backoff / 1000}s`)
    debug(`reconnecting in ${backoff}ms`)
    await Bun.sleep(backoff)
    backoff = Math.min(backoff * 2, BACKOFF_MAX_MS)
  }
}
