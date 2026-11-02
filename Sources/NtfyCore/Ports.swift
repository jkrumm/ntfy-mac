import Foundation

/// Time source. Production uses the system clock; tests advance a fake by hand.
public protocol Clock: Sendable {
  func now() -> Date
  func sleep(for duration: Duration) async throws
}

/// A live subscription to ntfy topics.
public protocol MessageStream: Sendable {
  /// Yields messages until the connection ends. A failure finishes the stream with an `NtfyError`
  /// (`AsyncThrowingStream` cannot carry a typed failure in the current stdlib).
  func messages(topics: [String], since: String?) -> AsyncThrowingStream<NtfyMessage, any Error>
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
}

/// Persistent message history.
public protocol HistoryStore: Sendable {
  func append(_ message: NtfyMessage) async throws(NtfyError)
  /// Newest first.
  func recent(limit: Int) async throws(NtfyError) -> [NtfyMessage]
  /// Id of the newest stored message, used as the stream resume cursor.
  func lastMessageID() async throws(NtfyError) -> String?
}

/// User-editable settings.
public protocol ConfigStore: Sendable {
  func load() async throws(NtfyError) -> Config
  func save(_ config: Config) async throws(NtfyError)
}
