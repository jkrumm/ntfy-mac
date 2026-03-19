import { describe, expect, it } from "bun:test"
import { buildOsaScript, capitalize, getSound, renderTags } from "../src/notify"
import type { NtfyMessage } from "../src/types"

describe("getSound", () => {
  it("priority 5 → Sosumi", () => expect(getSound(5)).toBe("Sosumi"))
  it("priority 4 → Ping", () => expect(getSound(4)).toBe("Ping"))
  it("priority 3 → Pop", () => expect(getSound(3)).toBe("Pop"))
  it("priority 2 → null", () => expect(getSound(2)).toBeNull())
  it("priority 1 → null", () => expect(getSound(1)).toBeNull())
  it("undefined priority defaults to Pop (priority 3)", () => expect(getSound()).toBe("Pop"))
})

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

describe("capitalize", () => {
  it("capitalizes first letter", () => expect(capitalize("hello")).toBe("Hello"))
  it("leaves already-capitalized string unchanged", () => expect(capitalize("Hello")).toBe("Hello"))
  it("handles empty string", () => expect(capitalize("")).toBe(""))
  it("handles single char", () => expect(capitalize("a")).toBe("A"))
})

describe("buildOsaScript", () => {
  it("produces valid display notification script", () => {
    const script = buildOsaScript({ title: "Test", body: "Hello" })
    expect(script).toContain('display notification "Hello"')
    expect(script).toContain('with title "Test"')
  })

  it("includes subtitle when provided", () => {
    const script = buildOsaScript({ title: "T", body: "B", subtitle: "S" })
    expect(script).toContain('subtitle "S"')
  })

  it("omits subtitle when not provided", () => {
    const script = buildOsaScript({ title: "T", body: "B" })
    expect(script).not.toContain("subtitle")
  })

  it("includes sound name when provided", () => {
    const script = buildOsaScript({ title: "T", body: "B", sound: "Pop" })
    expect(script).toContain('sound name "Pop"')
  })

  it("omits sound when null", () => {
    const script = buildOsaScript({ title: "T", body: "B", sound: null })
    expect(script).not.toContain("sound name")
  })

  it("omits sound when undefined", () => {
    const script = buildOsaScript({ title: "T", body: "B" })
    expect(script).not.toContain("sound name")
  })

  it("sanitizes double quotes in title", () => {
    const script = buildOsaScript({ title: 'Say "hello"', body: "B" })
    // Quotes inside the value should be backslash-escaped for AppleScript
    expect(script).toContain('\\"hello\\"')
  })

  it("sanitizes double quotes in body", () => {
    const script = buildOsaScript({ title: "T", body: 'He said "bye"' })
    expect(script).toContain('\\"bye\\"')
  })
})

describe("title fallback from topic", () => {
  it("uses msg.title when present", () => {
    // Test the logic that sendNotification uses (without calling osascript)
    const msg: NtfyMessage = {
      id: "1",
      time: 1700000000,
      topic: "alerts",
      title: "My Title",
      message: "body",
    }
    const title = msg.title ?? capitalize(msg.topic)
    expect(title).toBe("My Title")
  })

  it("falls back to capitalized topic when title is absent", () => {
    const msg: NtfyMessage = {
      id: "2",
      time: 1700000000,
      topic: "alerts",
      message: "body",
    }
    const title = msg.title ?? capitalize(msg.topic)
    expect(title).toBe("Alerts")
  })
})
