import NtfyCore

/// Keeps history in memory; a message with a known topic + id is not stored twice.
public actor InMemoryHistoryStore: HistoryStore {
  private var messages: [NtfyMessage] = []
  private var appendFailure: NtfyError?
  private var appendsBeforeFailure = 0

  public init() {}

  @discardableResult
  public func append(_ message: NtfyMessage) throws(NtfyError) -> Bool {
    if let appendFailure {
      if appendsBeforeFailure == 0 { throw appendFailure }
      appendsBeforeFailure -= 1
    }
    let isKnown = messages.contains { $0.topic == message.topic && $0.id == message.id }
    if isKnown { return false }
    messages.append(message)
    return true
  }

  /// Makes `append` throw `failure` once `successes` more appends went through, or work again
  /// with `nil`.
  public func setAppendFailure(_ failure: NtfyError?, afterSuccesses successes: Int = 0) {
    appendFailure = failure
    appendsBeforeFailure = successes
  }

  public func recent(limit: Int) -> [NtfyMessage] {
    Array(messages.reversed().prefix(max(limit, 0)))
  }

  public func lastMessageID() -> String? { messages.last?.id }
}
