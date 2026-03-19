import { describe, expect, it } from "bun:test"
import { categorizeMissedMessages, parseNtfyLine } from "../src/ntfy"
import type { NtfyMessage } from "../src/types"

const MINUTE = 60 * 1000
const HOUR = 60 * MINUTE

function makeMsg(overrides: Partial<NtfyMessage> & { ageMs?: number }): NtfyMessage {
  const { ageMs = 0, ...rest } = overrides
  const time = Math.floor((Date.now() - ageMs) / 1000)
  return {
    id: `id-${Math.random().toString(36).slice(2)}`,
    time,
    topic: "test",
    message: "hello",
    ...rest,
  }
}

describe("parseNtfyLine", () => {
  it("parses a complete message", () => {
    const msg: NtfyMessage = {
      id: "abc123",
      time: 1700000000,
      topic: "alerts",
      title: "Hello",
      message: "World",
      priority: 3,
      tags: ["warning"],
      click: "https://example.com",
    }
    const result = parseNtfyLine(JSON.stringify(msg))
    expect(result).toEqual(msg)
  })

  it("parses a minimal message (only required fields)", () => {
    const raw = JSON.stringify({ id: "x", time: 1700000000, topic: "t", message: "m" })
    const result = parseNtfyLine(raw)
    expect(result?.id).toBe("x")
    expect(result?.topic).toBe("t")
    expect(result?.title).toBeUndefined()
    expect(result?.tags).toBeUndefined()
  })

  it("returns null for invalid JSON", () => {
    expect(parseNtfyLine("not json at all")).toBeNull()
    expect(parseNtfyLine("{broken")).toBeNull()
  })

  it("returns null for empty/whitespace line", () => {
    expect(parseNtfyLine("")).toBeNull()
    expect(parseNtfyLine("   ")).toBeNull()
  })

  it("returns null when required fields are missing", () => {
    expect(parseNtfyLine(JSON.stringify({ id: "x", time: 1 }))).toBeNull() // no topic/message
    expect(parseNtfyLine(JSON.stringify({ topic: "t", message: "m" }))).toBeNull() // no id
  })

  it("does not throw on any input", () => {
    const inputs = ["null", "[]", "123", '{"nested":{"deep":true}}', "undefined"]
    for (const input of inputs) {
      expect(() => parseNtfyLine(input)).not.toThrow()
    }
  })
})

describe("categorizeMissedMessages", () => {
  it("returns silent for empty array", () => {
    expect(categorizeMissedMessages([])).toEqual({ type: "silent" })
  })

  it("3 messages 30min old → individual", () => {
    const messages = [
      makeMsg({ ageMs: 20 * MINUTE }),
      makeMsg({ ageMs: 25 * MINUTE }),
      makeMsg({ ageMs: 30 * MINUTE }),
    ]
    const result = categorizeMissedMessages(messages)
    expect(result.type).toBe("individual")
    if (result.type === "individual") {
      expect(result.messages).toHaveLength(3)
    }
  })

  it("8 messages 3h old → summary", () => {
    const messages = Array.from({ length: 8 }, (_, i) =>
      makeMsg({ ageMs: 3 * HOUR + i * MINUTE, topic: "alerts" }),
    )
    const result = categorizeMissedMessages(messages)
    expect(result.type).toBe("summary")
    if (result.type === "summary") {
      expect(result.count).toBe(8)
      expect(result.oldestTopic).toBe("alerts")
    }
  })

  it("5 messages 15h old → silent", () => {
    const messages = Array.from({ length: 5 }, (_, i) => makeMsg({ ageMs: 15 * HOUR + i * MINUTE }))
    expect(categorizeMissedMessages(messages)).toEqual({ type: "silent" })
  })

  it("exactly at 1h boundary → summary (not individual)", () => {
    const messages = [makeMsg({ ageMs: HOUR + 1000 })]
    expect(categorizeMissedMessages(messages).type).toBe("summary")
  })

  it("exactly at 12h boundary → silent", () => {
    const messages = [makeMsg({ ageMs: 12 * HOUR + 1000 })]
    expect(categorizeMissedMessages(messages).type).toBe("silent")
  })

  it("summary uses the topic of the oldest message", () => {
    const messages = [
      makeMsg({ ageMs: 2 * HOUR, topic: "recent-topic" }),
      makeMsg({ ageMs: 3 * HOUR, topic: "oldest-topic" }),
    ]
    const result = categorizeMissedMessages(messages)
    expect(result.type).toBe("summary")
    if (result.type === "summary") {
      expect(result.oldestTopic).toBe("oldest-topic")
    }
  })
})
