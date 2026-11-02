import NtfyCore

public actor InMemoryHistoryStore: HistoryStore {
  private var messages: [NtfyMessage] = []

  public init() {}

  public func append(_ message: NtfyMessage) {
    messages.append(message)
  }

  public func recent(limit: Int) -> [NtfyMessage] {
    Array(messages.reversed().prefix(max(limit, 0)))
  }

  public func lastMessageID() -> String? { messages.last?.id }
}
