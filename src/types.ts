export interface NtfyMessage {
  id: string
  time: number
  topic: string
  title?: string
  message: string
  priority?: 1 | 2 | 3 | 4 | 5
  tags?: string[]
  click?: string
}

export interface Config {
  url: string // e.g. https://ntfy.jkrumm.com
  token: string
  topics?: string[] // override auto-discovery
}

export interface AppState {
  seen: Record<string, number> // id → unix timestamp (ms)
  lastMessageId: string | null
  lastUpdateCheck: number | null // unix timestamp (ms)
  lastSetupNotification?: number | null // unix timestamp (ms)
  pendingUpdateNotification?: string | null // version string to notify on next startup
}
