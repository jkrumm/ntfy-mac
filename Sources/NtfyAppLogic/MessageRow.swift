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
  /// The sender sent a title; otherwise `title` is the first line of the body.
  public let hasTitle: Bool
  public let body: String
  /// The body is markdown, so a preview renders it instead of showing its syntax.
  public let isMarkdown: Bool
  /// The click URL, only when `URLPolicy.openable` lets it through.
  public let clickURL: URL?
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
    isMarkdown = message.isMarkdown
    clickURL = message.click.flatMap(URLPolicy.openable)
    title = Self.title(of: message)
    hasTitle = !(message.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    priority = message.priority
    time = message.time
    isRead = stored.isRead
    isAcknowledged = stored.isAcknowledged
  }

  /// What a list shows under the title: the body, or the rest of it when its first line already
  /// serves as the title. Line breaks stay; the view limits it to one line.
  public var preview: String {
    guard !hasTitle else { return body }
    let lines = body.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
    return lines.dropFirst().joined(separator: " ")
  }

  private static func title(of message: NtfyMessage) -> String {
    if let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
      return title
    }
    let firstLine = message.body.split(whereSeparator: \.isNewline).first.map(String.init)
    return firstLine?.trimmingCharacters(in: .whitespaces) ?? message.topic
  }
}
