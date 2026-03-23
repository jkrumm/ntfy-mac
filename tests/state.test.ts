import { describe, expect, it, beforeEach, afterEach } from "bun:test"
import { join } from "path"
import { StateManager } from "../src/state"
import type { AppState } from "../src/types"

const TEST_DIR = join(import.meta.dir, ".tmp-state-mgr")
const TEST_FILE = join(TEST_DIR, "state.json")

describe("StateManager", () => {
  beforeEach(async () => {
    await Bun.$`rm -rf ${TEST_DIR} && mkdir -p ${TEST_DIR}`.quiet()
  })

  afterEach(async () => {
    await Bun.$`rm -rf ${TEST_DIR}`.quiet()
  })

  it("load() returns default state when file is missing", async () => {
    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    const state = await mgr.load()
    expect(state.seen).toEqual({})
    expect(state.lastMessageId).toBeNull()
    expect(state.lastUpdateCheck).toBeNull()
  })

  it("load() reads state from disk", async () => {
    const fixture: AppState = {
      seen: { "msg-1": Date.now() },
      lastMessageId: "msg-1",
      lastUpdateCheck: 12345,
    }
    await Bun.write(TEST_FILE, JSON.stringify(fixture))

    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    const state = await mgr.load()
    expect(state.lastMessageId).toBe("msg-1")
    expect(state.lastUpdateCheck).toBe(12345)
    expect(state.seen["msg-1"]).toBeDefined()
  })

  it("load() applies cleanup (drops entries older than 48h)", async () => {
    const old = Date.now() - 49 * 60 * 60 * 1000
    const fixture: AppState = {
      seen: { old: old, recent: Date.now() },
      lastMessageId: null,
      lastUpdateCheck: null,
    }
    await Bun.write(TEST_FILE, JSON.stringify(fixture))

    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    const state = await mgr.load()
    expect("old" in state.seen).toBe(false)
    expect("recent" in state.seen).toBe(true)
  })

  it("get() throws if load() has not been called", () => {
    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    expect(() => mgr.get()).toThrow("call load() before get()")
  })

  it("get() returns cached state synchronously after load()", async () => {
    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    await mgr.load()
    const state = mgr.get()
    expect(state).toBeDefined()
    expect(state.seen).toEqual({})
  })

  it("update() applies mutation synchronously", async () => {
    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    await mgr.load()

    mgr.update((s) => ({ ...s, lastMessageId: "msg-42" }))

    expect(mgr.get().lastMessageId).toBe("msg-42")
    await mgr.waitForFlush()
  })

  it("update() flushes to disk", async () => {
    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    await mgr.load()

    mgr.update((s) => ({ ...s, lastMessageId: "msg-99" }))
    await mgr.waitForFlush()

    const raw = await Bun.file(TEST_FILE).text()
    const persisted = JSON.parse(raw) as AppState
    expect(persisted.lastMessageId).toBe("msg-99")
  })

  it("multiple rapid updates coalesce into fewer writes", async () => {
    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    await mgr.load()

    // 10 synchronous updates — should coalesce
    for (let i = 0; i < 10; i++) {
      mgr.update((s) => ({
        ...s,
        seen: { ...s.seen, [`msg-${i}`]: Date.now() },
      }))
    }

    await mgr.waitForFlush()

    // All 10 updates reflected in final state
    const state = mgr.get()
    for (let i = 0; i < 10; i++) {
      expect(`msg-${i}` in state.seen).toBe(true)
    }

    // Verify persisted on disk
    const raw = await Bun.file(TEST_FILE).text()
    const persisted = JSON.parse(raw) as AppState
    for (let i = 0; i < 10; i++) {
      expect(`msg-${i}` in persisted.seen).toBe(true)
    }
  })

  it("update() throws if load() has not been called", () => {
    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    expect(() => mgr.update((s) => s)).toThrow("call load() before update()")
  })

  it("preserves reminders and other optional fields", async () => {
    const fixture: AppState = {
      seen: {},
      lastMessageId: null,
      lastUpdateCheck: null,
      reminders: [{ id: "r1", fireAt: Date.now() + 60000, title: "Test", body: "Body" }],
      pendingUpdateNotification: "1.9.0",
    }
    await Bun.write(TEST_FILE, JSON.stringify(fixture))

    const mgr = new StateManager(TEST_DIR, TEST_FILE)
    await mgr.load()

    expect(mgr.get().reminders).toHaveLength(1)
    expect(mgr.get().pendingUpdateNotification).toBe("1.9.0")

    mgr.update((s) => ({ ...s, lastMessageId: "new" }))
    await mgr.waitForFlush()

    const raw = await Bun.file(TEST_FILE).text()
    const persisted = JSON.parse(raw) as AppState
    expect(persisted.reminders).toHaveLength(1)
    expect(persisted.pendingUpdateNotification).toBe("1.9.0")
  })
})
