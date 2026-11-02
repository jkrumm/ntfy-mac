import Foundation

/// Time source. Production uses the system clock; tests advance a fake by hand.
public protocol Clock: Sendable {
  func now() -> Date
  func sleep(for duration: Duration) async throws
}

/// A live subscription to ntfy topics.
public protocol MessageStream: Sendable {
  /// Yields every event of one connection. The contract for the consumer:
  /// - A normal finish means the server closed the connection cleanly; reconnect with `since`.
  /// - A failure finishes the stream with an `NtfyError` (`AsyncThrowingStream` cannot carry a
  ///   typed failure in the current stdlib).
  /// - A consumer stops the subscription by cancelling its own task; that never yields an error.
  func events(topics: [String], since: String?) -> AsyncThrowingStream<StreamEvent, any Error>
}

/// One-shot catch-up: the messages a topic cached after the given id.
public protocol MessagePoller: Sendable {
  func poll(topics: [String], since: String?) async throws(NtfyError) -> [NtfyMessage]
}

/// The topics the account is subscribed to on the server.
public protocol TopicSource: Sendable {
  func subscribedTopics() async throws(NtfyError) -> [String]
}

/// Id of the last message that was fully processed, the resume point after a restart.
public protocol CursorStore: Sendable {
  func load() async throws(NtfyError) -> String?
  func save(_ id: String) async throws(NtfyError)
}

/// Something that happened to the machine, independent of the server.
public enum SystemEvent: Sendable, Hashable {
  case didWake
  case willSleep
  case pathChanged(online: Bool)
}

/// Power and network changes of the host.
public protocol SystemEvents: Sendable {
  func events() -> AsyncStream<SystemEvent>
}

/// Where the access token is kept (the Keychain in production).
public protocol SecretStore: Sendable {
  func token() async throws(NtfyError) -> String?
  func setToken(_ token: String) async throws(NtfyError)
  func deleteToken() async throws(NtfyError)
}

/// Shows a message to the user.
public protocol NotificationPoster: Sendable {
  func post(_ message: NtfyMessage) async throws(NtfyError)
  /// One notification standing in for `count` messages that were missed while away.
  func postMissedSummary(count: Int, oldestTopic: String) async throws(NtfyError)
}

/// Persistent message history.
public protocol HistoryStore: Sendable {
  /// Returns `true` if the message was new; the dedup key is topic + id.
  @discardableResult
  func append(_ message: NtfyMessage) async throws(NtfyError) -> Bool
  /// Newest first.
  func recent(limit: Int) async throws(NtfyError) -> [NtfyMessage]
  /// Id of the newest stored message, used as the stream resume cursor.
  func lastMessageID() async throws(NtfyError) -> String?
}

/// User-editable settings.
public protocol ConfigStore: Sendable {
  func load() async throws(NtfyError) -> Config
  func save(_ config: Config) async throws(NtfyError)
  /// Read-modify-write as one step, so a concurrent writer's change is not reverted by a stale
  /// snapshot. Prefer this to `load` + `save` for anything but a full replace.
  func update(_ change: @Sendable (inout Config) -> Void) async throws(NtfyError)
}
