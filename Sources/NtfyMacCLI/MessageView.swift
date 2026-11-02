import Foundation
import NtfyCore

struct MessageAttachmentView: Encodable, Sendable, Equatable {
  let name: String?
  let url: String
  let type: String?
  let size: Int64?

  private enum CodingKeys: String, CodingKey { case name, url, type, size }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(url, forKey: .url)
    try container.encode(type, forKey: .type)
    try container.encode(size, forKey: .size)
  }
}

/// A stored message as `--json` consumers see it. The field names are a stable contract; absent
/// values are `null`, never missing.
struct MessageView: Encodable, Sendable, Equatable {
  let topic: String
  let id: String
  let time: Date
  let title: String?
  let message: String
  let priority: Int
  let tags: [String]
  let read: Bool
  let acknowledged: Bool
  let click: String?
  let attachments: [MessageAttachmentView]

  private enum CodingKeys: String, CodingKey {
    case topic, id, time, title, message, priority, tags, read, acknowledged, click, attachments
  }

  init(_ stored: StoredMessage) {
    let message = stored.message
    topic = message.topic
    id = message.id
    time = message.time
    title = message.title
    self.message = message.body
    priority = message.priority.rawValue
    tags = message.tags
    read = stored.isRead
    acknowledged = stored.isAcknowledged
    click = message.click?.absoluteString
    attachments =
      message.attachment.map {
        [
          MessageAttachmentView(
            name: $0.name, url: $0.url.absoluteString, type: $0.mimeType, size: $0.size)
        ]
      } ?? []
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(topic, forKey: .topic)
    try container.encode(id, forKey: .id)
    try container.encode(time, forKey: .time)
    try container.encode(title, forKey: .title)
    try container.encode(message, forKey: .message)
    try container.encode(priority, forKey: .priority)
    try container.encode(tags, forKey: .tags)
    try container.encode(read, forKey: .read)
    try container.encode(acknowledged, forKey: .acknowledged)
    try container.encode(click, forKey: .click)
    try container.encode(attachments, forKey: .attachments)
  }
}

/// The text renderings of messages.
enum MessageText {
  static func timestamp(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle())
  }

  /// One line per message, newest first as given: time, topic, priority, state, id, summary.
  static func table(_ entries: [StoredMessage]) -> String {
    guard !entries.isEmpty else { return "No messages." }
    let width = entries.map(\.message.topic.count).max() ?? 0
    return entries.map { entry in
      let message = entry.message
      let flags = (entry.isRead ? "-" : "U") + (entry.isAcknowledged ? "-" : "A")
      let topic = message.topic.padding(toLength: width, withPad: " ", startingAt: 0)
      return "\(timestamp(message.time))  \(topic)  p\(message.priority.rawValue)  \(flags)  "
        + "\(message.id)  \(summary(message))"
    }.joined(separator: "\n")
  }

  /// The complete message, for `read` and `wait`.
  static func full(_ entry: StoredMessage) -> String {
    let message = entry.message
    var lines = ["\(message.topic)/\(message.id)  \(timestamp(message.time))"]
    if let title = message.title, !title.isEmpty { lines.append("Title:    \(title)") }
    lines.append("Priority: \(message.priority.rawValue)")
    if !message.tags.isEmpty { lines.append("Tags:     \(message.tags.joined(separator: ", "))") }
    if let click = message.click { lines.append("Click:    \(click.absoluteString)") }
    if let attachment = message.attachment {
      lines.append("File:     \(attachment.name ?? attachment.url.lastPathComponent)")
      lines.append("          \(attachment.url.absoluteString)")
    }
    let state = entry.isRead ? "read" : "unread"
    lines.append("State:    \(state), \(entry.isAcknowledged ? "acknowledged" : "unacknowledged")")
    lines += ["", message.body]
    return lines.joined(separator: "\n")
  }

  private static func summary(_ message: NtfyMessage) -> String {
    let flat = message.body.split(whereSeparator: \.isNewline).joined(separator: " ")
    let text = flat.count > 80 ? flat.prefix(79) + "…" : flat
    guard let title = message.title, !title.isEmpty else { return String(text) }
    return "\(title): \(text)"
  }
}
