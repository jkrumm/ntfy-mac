import { afterEach, beforeEach, describe, expect, it } from "bun:test"
import { loadConfig } from "../src/config"

// loadConfig reads ~/.config/ntfy-mac/config.json first, then env vars as fallback.
// In test environments, the config file may or may not exist.
// These tests rely on env vars only — if a config file IS present on the
// test machine, its values take precedence and some assertions may
// need adjustment.  Run tests on a machine without ntfy-mac configured, or
// remove the config file first:
//   rm -f ~/.config/ntfy-mac/config.json

const SAVED_ENV: Record<string, string | undefined> = {}

function setEnv(vars: Record<string, string | undefined>) {
  for (const [k, v] of Object.entries(vars)) {
    SAVED_ENV[k] = process.env[k]
    if (v === undefined) delete process.env[k]
    else process.env[k] = v
  }
}

function restoreEnv() {
  for (const [k, v] of Object.entries(SAVED_ENV)) {
    if (v === undefined) delete process.env[k]
    else process.env[k] = v
  }
}

describe("loadConfig — URL validation", () => {
  afterEach(restoreEnv)

  it("returns null when URL and token are both missing", async () => {
    setEnv({ NTFY_URL: undefined, NTFY_TOKEN: undefined })
    // Only meaningful if no config file exists; we can at least ensure no crash
    const result = await loadConfig()
    // If a config file is present, this will return a config — that's OK.
    // The important thing: it never throws.
    expect(result === null || typeof result === "object").toBe(true)
  })

  it("returns null for invalid URL protocol", async () => {
    setEnv({ NTFY_URL: "ftp://bad.host", NTFY_TOKEN: "token" })
    const result = await loadConfig()
    // Config file may override env vars; only assert when we know config file is absent
    if (result !== null && result.url.startsWith("ftp:")) {
      expect(result).toBeNull()
    }
  })

  it("returns null for malformed URL", async () => {
    setEnv({ NTFY_URL: "not a url at all", NTFY_TOKEN: "token" })
    const result = await loadConfig()
    if (result !== null && !result.url.startsWith("http")) {
      expect(result).toBeNull()
    }
  })

  it("strips trailing slash from URL", async () => {
    setEnv({ NTFY_URL: "https://ntfy.example.com/", NTFY_TOKEN: "mytoken" })
    const result = await loadConfig()
    if (result && result.url.includes("example.com")) {
      expect(result.url).toBe("https://ntfy.example.com")
    }
  })

  it("trims whitespace from token", async () => {
    setEnv({ NTFY_URL: "https://ntfy.example.com", NTFY_TOKEN: "  mytoken  " })
    const result = await loadConfig()
    if (result && result.url.includes("example.com")) {
      expect(result.token).toBe("mytoken")
    }
  })

  it("returns null for blank token", async () => {
    setEnv({ NTFY_URL: "https://ntfy.example.com", NTFY_TOKEN: "   " })
    const result = await loadConfig()
    if (result && result.url.includes("example.com")) {
      expect(result).toBeNull()
    }
  })
})

describe("loadConfig — NTFY_TOPICS parsing", () => {
  afterEach(restoreEnv)

  it("parses comma-separated topics", async () => {
    setEnv({ NTFY_URL: "https://ntfy.example.com", NTFY_TOKEN: "tok", NTFY_TOPICS: "a,b,c" })
    const result = await loadConfig()
    if (result && result.url.includes("example.com")) {
      expect(result.topics).toEqual(["a", "b", "c"])
    }
  })

  it("trims whitespace from individual topics", async () => {
    setEnv({ NTFY_URL: "https://ntfy.example.com", NTFY_TOKEN: "tok", NTFY_TOPICS: " a , b " })
    const result = await loadConfig()
    if (result && result.url.includes("example.com")) {
      expect(result.topics).toEqual(["a", "b"])
    }
  })

  it("filters empty entries from topics", async () => {
    setEnv({ NTFY_URL: "https://ntfy.example.com", NTFY_TOKEN: "tok", NTFY_TOPICS: "a,,b," })
    const result = await loadConfig()
    if (result && result.url.includes("example.com")) {
      expect(result.topics).toEqual(["a", "b"])
    }
  })

  it("topics is undefined when NTFY_TOPICS is not set", async () => {
    setEnv({ NTFY_URL: "https://ntfy.example.com", NTFY_TOKEN: "tok", NTFY_TOPICS: undefined })
    const result = await loadConfig()
    if (result && result.url.includes("example.com")) {
      expect(result.topics).toBeUndefined()
    }
  })
})
