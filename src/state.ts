import { homedir } from "os"
import { cleanup } from "./dedup"
import type { AppState } from "./types"

export const STATE_DIR = `${homedir()}/.local/share/ntfy-mac`
export const STATE_FILE = `${STATE_DIR}/state.json`

const DEFAULT_STATE: AppState = {
  seen: {},
  lastMessageId: null,
  lastUpdateCheck: null,
}

/**
 * Single owner of AppState — reads disk once, serves from memory thereafter.
 *
 * Writes are coalesced: rapid `update()` calls in the same microtask batch
 * result in a single disk flush. This eliminates the read-modify-write race
 * condition where multiple async callers could clobber each other's changes.
 *
 * Supports dependency injection of file paths for testing.
 */
// ─── Standalone functions for non-daemon callers (CLI commands, updater) ──────

export async function loadState(): Promise<AppState> {
  try {
    const raw = await Bun.file(STATE_FILE).text()
    return cleanup(JSON.parse(raw) as AppState)
  } catch {
    return { ...DEFAULT_STATE }
  }
}

export async function saveState(state: AppState): Promise<void> {
  await Bun.$`mkdir -p ${STATE_DIR}`.quiet()
  const tmp = STATE_FILE + ".tmp"
  await Bun.write(tmp, JSON.stringify(state, null, 2))
  await Bun.$`mv ${tmp} ${STATE_FILE}`.quiet()
}

// ─── StateManager (daemon mode) ─────────────────────────────────────────────

export class StateManager {
  private state: AppState | null = null
  private dirty = false
  private flushChain: Promise<void> = Promise.resolve()

  constructor(
    private readonly stateDir = STATE_DIR,
    private readonly stateFile = STATE_FILE,
  ) {}

  /** Read state from disk (once). Applies cleanup on load. */
  async load(): Promise<AppState> {
    try {
      const raw = await Bun.file(this.stateFile).text()
      this.state = cleanup(JSON.parse(raw) as AppState)
    } catch {
      this.state = { ...DEFAULT_STATE }
    }
    return this.state
  }

  /** Synchronous read — throws if load() hasn't been called. */
  get(): AppState {
    if (!this.state) throw new Error("StateManager: call load() before get()")
    return this.state
  }

  /**
   * Apply a mutation synchronously. The caller sees the updated state immediately.
   * Disk flush is deferred to the next microtask and coalesced — multiple synchronous
   * update() calls result in a single disk write.
   */
  update(fn: (state: AppState) => AppState): void {
    if (!this.state) throw new Error("StateManager: call load() before update()")
    this.state = fn(this.state)
    if (!this.dirty) {
      this.dirty = true
      this.flushChain = this.flushChain.then(() => this.doFlush())
    }
  }

  /** Wait for any pending flush to complete. Useful for tests and shutdown. */
  async waitForFlush(): Promise<void> {
    await this.flushChain
  }

  /** Defers one microtask to coalesce synchronous updates, then flushes. */
  private async doFlush(): Promise<void> {
    await Promise.resolve()
    if (!this.dirty || !this.state) return
    this.dirty = false
    try {
      await Bun.$`mkdir -p ${this.stateDir}`.quiet()
      const tmp = this.stateFile + ".tmp"
      await Bun.write(tmp, JSON.stringify(this.state, null, 2))
      await Bun.$`mv ${tmp} ${this.stateFile}`.quiet()
    } catch (err) {
      console.error("state: flush failed:", err)
    }
  }
}
