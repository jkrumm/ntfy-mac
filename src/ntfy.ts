import type { Config, NtfyMessage } from "./types"
import { loadState, saveState, markSeen } from "./dedup"

// Missed-message categorization thresholds
const INDIVIDUAL_THRESHOLD_MS = 1 * 60 * 60 * 1000 // < 1h → show individually
const SILENT_THRESHOLD_MS = 12 * 60 * 60 * 1000 // > 12h → silent

// Exponential backoff config
const BACKOFF_INITIAL_MS = 5_000
const BACKOFF_MAX_MS = 5 * 60 * 1000

// Alert user after this many consecutive SSE failures (~30min at max backoff)
// Math: failures 1-5 burn through short backoffs (5+10+20+40+80s = ~2.5min),
// then each failure waits 5min. Threshold 12 ≈ 5min ramp + 7×5min ≈ 40min offline.
const FAILURE_ALERT_THRESHOLD = 12

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

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split("\n")
    buffer = lines.pop() ?? ""
    for (const line of lines) {
      if (!line.startsWith("data: ")) continue
      const msg = parseNtfyLine(line.slice(6))
      if (msg) await onMessage(msg)
    }
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
      await connectSSE(config, topics, since, async (msg) => {
        state = await loadState()
        state = { ...state, lastMessageId: msg.id }
        await saveState(state)
        since = msg.id
        backoff = BACKOFF_INITIAL_MS
        consecutiveFailures = 0
        await onMessage(msg)
      })
      // SSE ended cleanly — reconnect immediately at current backoff
    } catch (err) {
      consecutiveFailures++
      console.error(
        `ntfy connection error (attempt ${consecutiveFailures}):`,
        err instanceof Error ? err.message : err,
      )

      // Alert user after sustained failure
      if (consecutiveFailures === FAILURE_ALERT_THRESHOLD && onConnectionFailure) {
        await onConnectionFailure().catch(() => {})
      }
    }

    // Poll for any messages missed during the gap
    try {
      if (since !== "latest") {
        const missed = await pollMessages(config, topics, since)
        const unseen = missed.filter((m) => !state.seen[m.id])
        if (unseen.length > 0) {
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
      console.error("ntfy poll error:", pollErr instanceof Error ? pollErr.message : pollErr)
    }

    await Bun.sleep(backoff)
    backoff = Math.min(backoff * 2, BACKOFF_MAX_MS)
  }
}
