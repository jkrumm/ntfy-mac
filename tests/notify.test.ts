import { describe, expect, it } from "bun:test"
import {
  PRIORITY_CONFIG,
  buildNtfyPayload,
  capitalize,
  getSound,
  mapActions,
  renderTags,
  selectImageUrl,
  type NtfyNotificationPayload,
} from "../src/notify"
import type { NtfyMessage } from "../src/types"

// ─── PRIORITY_CONFIG ──────────────────────────────────────────────────────────

describe("PRIORITY_CONFIG", () => {
  it("priority 5 → Sosumi + time-sensitive + relevanceScore 1.0", () => {
    expect(PRIORITY_CONFIG[5]).toEqual({
      sound: "Sosumi",
      interruptionLevel: "time-sensitive",
      relevanceScore: 1.0,
    })
  })

  it("priority 4 → Ping + time-sensitive + relevanceScore 0.75", () => {
    expect(PRIORITY_CONFIG[4]).toEqual({
      sound: "Ping",
      interruptionLevel: "time-sensitive",
      relevanceScore: 0.75,
    })
  })

  it("priority 3 → Pop + active + relevanceScore 0.5", () => {
    expect(PRIORITY_CONFIG[3]).toEqual({
      sound: "Pop",
      interruptionLevel: "active",
      relevanceScore: 0.5,
    })
  })

  it("priority 2 → null + active + relevanceScore 0.25", () => {
    expect(PRIORITY_CONFIG[2]).toEqual({
      sound: null,
      interruptionLevel: "active",
      relevanceScore: 0.25,
    })
  })

  it("priority 1 → null + passive + relevanceScore 0.0", () => {
    expect(PRIORITY_CONFIG[1]).toEqual({
      sound: null,
      interruptionLevel: "passive",
      relevanceScore: 0.0,
    })
  })
})

// ─── getSound ─────────────────────────────────────────────────────────────────

describe("getSound", () => {
  it("priority 5 → Sosumi", () => expect(getSound(5)).toBe("Sosumi"))
  it("priority 4 → Ping", () => expect(getSound(4)).toBe("Ping"))
  it("priority 3 → Pop", () => expect(getSound(3)).toBe("Pop"))
  it("priority 2 → null (silent)", () => expect(getSound(2)).toBeNull())
  it("priority 1 → null (silent)", () => expect(getSound(1)).toBeNull())
  it("undefined priority defaults to Pop (priority 3)", () => expect(getSound()).toBe("Pop"))
})

// ─── renderTags ───────────────────────────────────────────────────────────────

describe("renderTags", () => {
  it("known tags → emoji", () => {
    expect(renderTags(["warning"])).toBe("⚠️")
    expect(renderTags(["rotating_light"])).toBe("🚨")
    expect(renderTags(["+1"])).toBe("👍")
    expect(renderTags(["white_check_mark"])).toBe("✅")
  })

  it("unknown tags → passed through as-is", () => {
    expect(renderTags(["my-custom-tag"])).toBe("my-custom-tag")
  })

  it("mixed known and unknown tags", () => {
    expect(renderTags(["fire", "custom"])).toBe("🔥 custom")
  })

  it("multiple known tags joined by space", () => {
    expect(renderTags(["warning", "+1"])).toBe("⚠️ 👍")
  })

  it("empty array → empty string", () => {
    expect(renderTags([])).toBe("")
  })

  it("undefined → empty string", () => {
    expect(renderTags(undefined)).toBe("")
  })
})

// ─── capitalize ───────────────────────────────────────────────────────────────

describe("capitalize", () => {
  it("capitalizes first letter", () => expect(capitalize("hello")).toBe("Hello"))
  it("leaves already-capitalized string unchanged", () => expect(capitalize("Hello")).toBe("Hello"))
  it("handles empty string", () => expect(capitalize("")).toBe(""))
  it("handles single char", () => expect(capitalize("a")).toBe("A"))
})

// ─── selectImageUrl ───────────────────────────────────────────────────────────

describe("selectImageUrl", () => {
  const base: NtfyMessage = { id: "1", time: 1700000000, topic: "t", message: "m" }

  it("prefers attachment.url when mime starts with image/", () => {
    const msg = {
      ...base,
      attachment: { url: "https://example.com/img.png", type: "image/png" },
      icon: "https://example.com/icon.png",
    }
    expect(selectImageUrl(msg)).toBe("https://example.com/img.png")
  })

  it("falls back to icon when attachment mime is not an image", () => {
    const msg = {
      ...base,
      attachment: { url: "https://example.com/file.pdf", type: "application/pdf" },
      icon: "https://example.com/icon.png",
    }
    expect(selectImageUrl(msg)).toBe("https://example.com/icon.png")
  })

  it("falls back to icon when no attachment", () => {
    const msg = { ...base, icon: "https://example.com/icon.png" }
    expect(selectImageUrl(msg)).toBe("https://example.com/icon.png")
  })

  it("returns undefined when neither attachment nor icon", () => {
    expect(selectImageUrl(base)).toBeUndefined()
  })

  it("returns attachment.url when attachment has no type (undefined)", () => {
    const msg = { ...base, attachment: { url: "https://example.com/img.png" } }
    // No type → not an image mime → falls back to icon (undefined)
    expect(selectImageUrl(msg)).toBeUndefined()
  })
})

// ─── mapActions ───────────────────────────────────────────────────────────────

describe("mapActions", () => {
  const base: NtfyMessage = { id: "abc12345", time: 1700000000, topic: "t", message: "m" }

  it("returns empty array when no actions", () => {
    expect(mapActions(base)).toEqual([])
  })

  it("maps view action with url", () => {
    const msg = {
      ...base,
      actions: [{ action: "view" as const, label: "Open Link", url: "https://example.com" }],
    }
    const result = mapActions(msg)
    expect(result).toHaveLength(1)
    expect(result[0].identifier).toBe("view-open-link")
    expect(result[0].title).toBe("Open Link")
    expect(result[0].url).toBe("https://example.com")
    expect(result[0].httpUrl).toBeUndefined()
  })

  it("maps http action with url, method, headers, body", () => {
    const msg = {
      ...base,
      actions: [
        {
          action: "http" as const,
          label: "Ack",
          url: "https://api.example.com/ack",
          method: "PUT",
          headers: { "X-Token": "abc" },
          body: '{"ok":true}',
        },
      ],
    }
    const result = mapActions(msg)
    expect(result).toHaveLength(1)
    expect(result[0].identifier).toBe("http-ack")
    expect(result[0].httpUrl).toBe("https://api.example.com/ack")
    expect(result[0].httpMethod).toBe("PUT")
    expect(result[0].httpHeaders).toEqual({ "X-Token": "abc" })
    expect(result[0].httpBody).toBe('{"ok":true}')
    expect(result[0].url).toBeUndefined()
  })

  it("filters out broadcast and copy actions", () => {
    const msg = {
      ...base,
      actions: [
        { action: "broadcast" as const, label: "Broadcast" },
        { action: "copy" as const, label: "Copy" },
        { action: "view" as const, label: "View", url: "https://example.com" },
      ],
    }
    const result = mapActions(msg)
    expect(result).toHaveLength(1)
    expect(result[0].title).toBe("View")
  })

  it("http action defaults method to POST when omitted", () => {
    const msg = {
      ...base,
      actions: [{ action: "http" as const, label: "Fire", url: "https://example.com/hook" }],
    }
    expect(mapActions(msg)[0].httpMethod).toBe("POST")
  })

  it("duplicate action labels get unique identifiers", () => {
    const msg = {
      ...base,
      actions: [
        { action: "view" as const, label: "Open", url: "https://a.example.com" },
        { action: "view" as const, label: "Open", url: "https://b.example.com" },
      ],
    }
    const result = mapActions(msg)
    expect(result).toHaveLength(2)
    expect(result[0].identifier).toBe("view-open")
    expect(result[1].identifier).toBe("view-open-1")
  })
})

// ─── buildNtfyPayload ─────────────────────────────────────────────────────────

describe("buildNtfyPayload", () => {
  const base: NtfyMessage = {
    id: "abc12345",
    time: 1700000000,
    topic: "alerts",
    message: "body text",
  }

  it("uses msg.title when present", () => {
    const payload = buildNtfyPayload({ ...base, title: "Custom Title" })
    expect(payload.title).toBe("Custom Title")
  })

  it("falls back to capitalized topic when title is absent", () => {
    expect(buildNtfyPayload(base).title).toBe("Alerts")
  })

  it("subtitle is just topic when no tags", () => {
    expect(buildNtfyPayload(base).subtitle).toBe("alerts")
  })

  it("subtitle includes tags separated by bullet when tags present", () => {
    const payload = buildNtfyPayload({ ...base, tags: ["fire", "warning"] })
    expect(payload.subtitle).toBe("alerts • 🔥 ⚠️")
  })

  it("body is the message", () => {
    expect(buildNtfyPayload(base).body).toBe("body text")
  })

  it("threadId is the topic name", () => {
    expect(buildNtfyPayload(base).threadId).toBe("alerts")
  })

  it("default priority → Pop + active + 0.5", () => {
    const p = buildNtfyPayload(base)
    expect(p.sound).toBe("Pop")
    expect(p.interruptionLevel).toBe("active")
    expect(p.relevanceScore).toBe(0.5)
  })

  it("priority 5 → Sosumi + time-sensitive + 1.0", () => {
    const p = buildNtfyPayload({ ...base, priority: 5 })
    expect(p.sound).toBe("Sosumi")
    expect(p.interruptionLevel).toBe("time-sensitive")
    expect(p.relevanceScore).toBe(1.0)
  })

  it("priority 4 → Ping + time-sensitive + 0.75", () => {
    const p = buildNtfyPayload({ ...base, priority: 4 })
    expect(p.sound).toBe("Ping")
    expect(p.interruptionLevel).toBe("time-sensitive")
    expect(p.relevanceScore).toBe(0.75)
  })

  it("priority 2 → null + active + 0.25", () => {
    const p = buildNtfyPayload({ ...base, priority: 2 })
    expect(p.sound).toBeNull()
    expect(p.interruptionLevel).toBe("active")
    expect(p.relevanceScore).toBe(0.25)
  })

  it("priority 1 → null + passive + 0.0", () => {
    const p = buildNtfyPayload({ ...base, priority: 1 })
    expect(p.sound).toBeNull()
    expect(p.interruptionLevel).toBe("passive")
    expect(p.relevanceScore).toBe(0.0)
  })

  it("click field → clickUrl in payload (not immediately opened)", () => {
    const p = buildNtfyPayload({ ...base, click: "https://example.com" })
    expect(p.clickUrl).toBe("https://example.com")
  })

  it("no click field → no clickUrl in payload", () => {
    expect(buildNtfyPayload(base).clickUrl).toBeUndefined()
  })

  it("image attachment → imageUrl from attachment.url", () => {
    const p = buildNtfyPayload({
      ...base,
      attachment: { url: "https://example.com/img.png", type: "image/png" },
    })
    expect(p.imageUrl).toBe("https://example.com/img.png")
  })

  it("icon fallback when no image attachment", () => {
    const p = buildNtfyPayload({ ...base, icon: "https://example.com/icon.png" })
    expect(p.imageUrl).toBe("https://example.com/icon.png")
  })

  it("view action mapped → actions + categoryId in payload", () => {
    const p = buildNtfyPayload({
      ...base,
      actions: [{ action: "view", label: "Open", url: "https://example.com" }],
    })
    expect(p.actions).toHaveLength(1)
    expect(p.categoryId).toBe("ntfy-abc12345")
  })

  it("broadcast/copy actions filtered → no actions in payload", () => {
    const p = buildNtfyPayload({
      ...base,
      actions: [
        { action: "broadcast", label: "B" },
        { action: "copy", label: "C" },
      ],
    })
    expect(p.actions).toBeUndefined()
    expect(p.categoryId).toBeUndefined()
  })

  it("returns correct shape", () => {
    const payload: NtfyNotificationPayload = buildNtfyPayload(base)
    expect(payload).toMatchObject({
      title: "Alerts",
      subtitle: "alerts",
      body: "body text",
      threadId: "alerts",
      interruptionLevel: "active",
      relevanceScore: 0.5,
    })
  })
})

// ─── Payload round-trip (JSON serialization sanity check) ─────────────────────

describe("payload JSON serialization", () => {
  it("serializes cleanly without undefined fields", () => {
    const payload = buildNtfyPayload({
      id: "abc12345",
      time: 1700000000,
      topic: "test",
      message: "hello",
    })
    const json = JSON.stringify(payload, (_k, v) => (v === undefined ? undefined : v))
    const parsed = JSON.parse(json)
    expect(parsed.title).toBe("Test")
    expect(parsed.body).toBe("hello")
    expect(parsed.threadId).toBe("test")
    expect("clickUrl" in parsed).toBe(false)
  })

  it("special characters in title/body don't require escaping (JSON handles it)", () => {
    const payload = buildNtfyPayload({
      id: "abc12345",
      time: 1700000000,
      topic: "test",
      title: 'Say "hello" world\\here',
      message: "Line1\nLine2",
    })
    const parsed = JSON.parse(JSON.stringify(payload))
    expect(parsed.title).toBe('Say "hello" world\\here')
    expect(parsed.body).toBe("Line1\nLine2")
  })

  it("click URL survives JSON round-trip", () => {
    const payload = buildNtfyPayload({
      id: "abc12345",
      time: 1700000000,
      topic: "test",
      message: "hello",
      click: "https://example.com/path?q=1&r=2",
    })
    const parsed = JSON.parse(JSON.stringify(payload))
    expect(parsed.clickUrl).toBe("https://example.com/path?q=1&r=2")
  })
})
