/**
 * Pure deduplication functions — no I/O, no side effects.
 *
 * State persistence lives in state.ts (StateManager for daemon,
 * standalone loadState/saveState for CLI commands).
 */

import type { AppState } from "./types"

const FORTY_EIGHT_HOURS_MS = 48 * 60 * 60 * 1000
const MAX_SEEN_ENTRIES = 1000

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
