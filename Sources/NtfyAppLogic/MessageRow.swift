import Foundation
import NtfyCore

/// A message's identity across the UI: the history key, without the server origin.
public struct MessageKey: Sendable, Hashable {
  public let topic: String
  public let id: String

  public init(topic: String, id: String) {
    self.topic = topic
    self.id = id
  }
}

/// One message as a list shows it. Plain values, no markdown, nothing from SwiftUI.
public struct MessageRow: Sendable, Hashable, Identifiable {
  public let key: MessageKey
  /// The message title, else the first line of the body.
  public let title: String
  public let body: String
  public let priority: Priority
  public let time: Date
  public let isRead: Bool
  public let isAcknowledged: Bool

  public var id: String { "\(key.topic)/\(key.id)" }
  public var topic: String { key.topic }
  /// High or urgent: worth a marker.
  public var isUrgent: Bool { priority >= .high }

  public init(_ stored: StoredMessage) {
    let message = stored.message
    key = MessageKey(topic: message.topic, id: message.id)
    body = message.body
    title = Self.title(of: message)
    priority = message.priority
    time = message.time
    isRead = stored.isRead
    isAcknowledged = stored.isAcknowledged
  }

  private static func title(of message: NtfyMessage) -> String {
    if let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
      return title
    }
    let firstLine = message.body.split(whereSeparator: \.isNewline).first.map(String.init)
    return firstLine?.trimmingCharacters(in: .whitespaces) ?? message.topic
  }
}
