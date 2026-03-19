import type { AppState } from "./types"

const STATE_DIR = `${process.env.HOME}/.local/share/ntfy-mac`
const STATE_FILE = `${STATE_DIR}/state.json`

const FORTY_EIGHT_HOURS_MS = 48 * 60 * 60 * 1000
const MAX_SEEN_ENTRIES = 1000

const DEFAULT_STATE: AppState = {
  seen: {},
  lastMessageId: null,
  lastUpdateCheck: null,
}

export async function loadState(): Promise<AppState> {
  try {
    const raw = await Bun.file(STATE_FILE).text()
    const parsed = JSON.parse(raw) as AppState
    return cleanup(parsed)
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

export function cleanup(state: AppState): AppState {
  const cutoff = Date.now() - FORTY_EIGHT_HOURS_MS
  const entries = Object.entries(state.seen).filter(([, ts]) => ts > cutoff)

  // Keep only the 1000 most recent
  const trimmed = entries.sort(([, a], [, b]) => b - a).slice(0, MAX_SEEN_ENTRIES)

  return {
    ...state,
    seen: Object.fromEntries(trimmed),
  }
}

export function isSeen(state: AppState, id: string): boolean {
  return id in state.seen
}

export function markSeen(state: AppState, id: string): AppState {
  return {
    ...state,
    seen: { ...state.seen, [id]: Date.now() },
  }
}
