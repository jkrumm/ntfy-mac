export interface NtfyAttachment {
  url: string
  name?: string
  size?: number
  type?: string // mime type, e.g. "image/png"
  expires?: number
}

export interface NtfyAction {
  action: "view" | "broadcast" | "http" | "copy"
  label: string
  url?: string // view / http target
  method?: string // http: GET/POST/PUT
  headers?: Record<string, string>
  body?: string
  clear?: boolean // dismiss after action
}

export interface NtfyMessage {
  id: string
  time: number
  topic: string
  title?: string
  message: string
  priority?: 1 | 2 | 3 | 4 | 5
  tags?: string[]
  click?: string
  attachment?: NtfyAttachment // image shown inline in notification
  icon?: string // fallback thumbnail if no image attachment
  actions?: NtfyAction[] // action buttons (view/http supported; broadcast/copy skipped)
  expires?: number // informational only
  event?: string // filter keepalive/open events
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
