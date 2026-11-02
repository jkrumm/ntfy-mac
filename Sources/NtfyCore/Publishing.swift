import Foundation

/// A message to publish to a topic on the configured server.
public struct PublishRequest: Sendable, Hashable {
  public var topic: String
  public var message: String
  public var title: String?
  /// 1...5; nil lets the server pick its default.
  public var priority: Priority?
  public var tags: [String]
  public var click: URL?

  public init(
    topic: String, message: String, title: String? = nil, priority: Priority? = nil,
    tags: [String] = [], click: URL? = nil
  ) {
    self.topic = topic
    self.message = message
    self.title = title
    self.priority = priority
    self.tags = tags
    self.click = click
  }
}

/// What the server reports for a published message.
public struct PublishedMessage: Sendable, Hashable {
  public let id: String
  public let topic: String
  public let time: Date

  public init(id: String, topic: String, time: Date) {
    self.id = id
    self.topic = topic
    self.time = time
  }
}

/// Publishes messages to the server (`POST`).
public protocol NtfyPublishing: Sendable {
  func publish(_ request: PublishRequest) async throws(NtfyError) -> PublishedMessage
}

/// Whether the app starts at login, as macOS reports it for the main app.
public enum LoginItemState: String, Sendable, Hashable, CaseIterable, Codable {
  case enabled
  /// Registered, but the user has to approve it in System Settings.
  case requiresApproval
  case notRegistered
  case notFound

  /// Runs at the next login without further user action.
  public var isEnabled: Bool { self == .enabled }
}

/// The app's registration as a login item. Only the app process can change its own registration.
public protocol LoginItemControlling: Sendable {
  func state() -> LoginItemState
  /// Registers or unregisters, then reports the resulting state.
  func setEnabled(_ enabled: Bool) throws(NtfyError) -> LoginItemState
}
