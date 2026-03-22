import { describe, expect, it } from "bun:test"
import {
  PRIORITY_CONFIG,
  buildNtfyPayload,
  capitalize,
  getSound,
  mapActions,
  renderTags,
  resolvePriorityConfig,
  selectImageUrl,
  type NtfyNotificationPayload,
} from "../src/notify"
import type { NtfyMessage } from "../src/types"

// ─── PRIORITY_CONFIG ──────────────────────────────────────────────────────────

describe("PRIORITY_CONFIG", () => {
  it("priority 5 → Ping + time-sensitive + relevanceScore 1.0 + never dismiss", () => {
    expect(PRIORITY_CONFIG[5]).toEqual({
      sound: "Ping",
      interruptionLevel: "time-sensitive",
      relevanceScore: 1.0,
      dismissAfter: 0,
    })
  })

  it("priority 4 → Ping + time-sensitive + relevanceScore 0.75 + never dismiss", () => {
    expect(PRIORITY_CONFIG[4]).toEqual({
      sound: "Ping",
      interruptionLevel: "time-sensitive",
      relevanceScore: 0.75,
      dismissAfter: 0,
    })
  })

  it("priority 3 → Pop + active + relevanceScore 0.5 + dismiss 7s", () => {
    expect(PRIORITY_CONFIG[3]).toEqual({
      sound: "Pop",
      interruptionLevel: "active",
      relevanceScore: 0.5,
      dismissAfter: 7,
    })
  })

  it("priority 2 → Tink + active + relevanceScore 0.25 + dismiss 5s", () => {
    expect(PRIORITY_CONFIG[2]).toEqual({
      sound: "Tink",
      interruptionLevel: "active",
      relevanceScore: 0.25,
      dismissAfter: 5,
    })
  })

  it("priority 1 → Tink + active + relevanceScore 0.0 + dismiss 3s", () => {
    expect(PRIORITY_CONFIG[1]).toEqual({
      sound: "Tink",
      interruptionLevel: "active",
      relevanceScore: 0.0,
      dismissAfter: 3,
    })
  })
})

// ─── getSound ─────────────────────────────────────────────────────────────────

describe("getSound", () => {
  it("priority 5 → Ping", () => expect(getSound(5)).toBe("Ping"))
  it("priority 4 → Ping", () => expect(getSound(4)).toBe("Ping"))
  it("priority 3 → Pop", () => expect(getSound(3)).toBe("Pop"))
  it("priority 2 → Tink", () => expect(getSound(2)).toBe("Tink"))
  it("priority 1 → Tink", () => expect(getSound(1)).toBe("Tink"))
  it("undefined priority defaults to Pop (priority 3)", () => expect(getSound()).toBe("Pop"))

  it("respects sound overrides", () => {
    expect(getSound(5, { "5": "Glass" })).toBe("Glass")
  })

  it("override null makes sound silent", () => {
    expect(getSound(3, { "3": null })).toBeNull()
  })

  it("unoverridden priorities keep defaults", () => {
    expect(getSound(4, { "5": "Glass" })).toBe("Ping")
  })
})

// ─── resolvePriorityConfig ───────────────────────────────────────────────────

describe("resolvePriorityConfig", () => {
  it("returns defaults when no overrides", () => {
    expect(resolvePriorityConfig(5)).toEqual(PRIORITY_CONFIG[5])
  })

  it("returns defaults when overrides is undefined", () => {
    expect(resolvePriorityConfig(3, undefined)).toEqual(PRIORITY_CONFIG[3])
  })

  it("overrides sound only, keeps interruptionLevel and relevanceScore", () => {
    const result = resolvePriorityConfig(5, { "5": "Tink" })
    expect(result.sound).toBe("Tink")
    expect(result.interruptionLevel).toBe("time-sensitive")
    expect(result.relevanceScore).toBe(1.0)
  })

  it("override to null makes priority silent", () => {
    const result = resolvePriorityConfig(3, { "3": null })
    expect(result.sound).toBeNull()
    expect(result.interruptionLevel).toBe("active")
  })

  it("overrides dismissAfter, keeps other fields", () => {
    const result = resolvePriorityConfig(3, undefined, { "3": 20 })
    expect(result.dismissAfter).toBe(20)
    expect(result.sound).toBe("Pop")
    expect(result.interruptionLevel).toBe("active")
  })

  it("dismiss override 0 means never", () => {
    const result = resolvePriorityConfig(3, undefined, { "3": 0 })
    expect(result.dismissAfter).toBe(0)
  })

  it("falls back to priority 3 for unknown priority", () => {
    expect(resolvePriorityConfig(99)).toEqual(PRIORITY_CONFIG[3])
  })
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

  it("default priority → Pop + active + 0.5 + dismiss 7s", () => {
    const p = buildNtfyPayload(base)
    expect(p.sound).toBe("Pop")
    expect(p.interruptionLevel).toBe("active")
    expect(p.relevanceScore).toBe(0.5)
    expect(p.dismissAfter).toBe(7)
  })

  it("priority 5 → Ping + time-sensitive + 1.0 + no dismiss", () => {
    const p = buildNtfyPayload({ ...base, priority: 5 })
    expect(p.sound).toBe("Ping")
    expect(p.interruptionLevel).toBe("time-sensitive")
    expect(p.relevanceScore).toBe(1.0)
    expect(p.dismissAfter).toBeUndefined()
  })

  it("priority 4 → Ping + time-sensitive + 0.75 + no dismiss", () => {
    const p = buildNtfyPayload({ ...base, priority: 4 })
    expect(p.sound).toBe("Ping")
    expect(p.interruptionLevel).toBe("time-sensitive")
    expect(p.relevanceScore).toBe(0.75)
    expect(p.dismissAfter).toBeUndefined()
  })

  it("priority 2 → Tink + active + 0.25 + dismiss 5s", () => {
    const p = buildNtfyPayload({ ...base, priority: 2 })
    expect(p.sound).toBe("Tink")
    expect(p.interruptionLevel).toBe("active")
    expect(p.relevanceScore).toBe(0.25)
    expect(p.dismissAfter).toBe(5)
  })

  it("priority 1 → Tink + active + 0.0 + dismiss 3s", () => {
    const p = buildNtfyPayload({ ...base, priority: 1 })
    expect(p.sound).toBe("Tink")
    expect(p.interruptionLevel).toBe("active")
    expect(p.relevanceScore).toBe(0.0)
    expect(p.dismissAfter).toBe(3)
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

  it("applies sound overrides when provided", () => {
    const p = buildNtfyPayload({ ...base, priority: 5 }, { "5": "Glass" })
    expect(p.sound).toBe("Glass")
    expect(p.interruptionLevel).toBe("time-sensitive") // unchanged
  })

  it("override to silent respects null", () => {
    const p = buildNtfyPayload({ ...base, priority: 3 }, { "3": null })
    expect(p.sound).toBeNull()
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
