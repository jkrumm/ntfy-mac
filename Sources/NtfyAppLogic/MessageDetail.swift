import Foundation
import NtfyCore

/// One message as the detail pane shows it. Plain values; the view renders markdown, images and
/// emoji from them.
public struct MessageDetail: Sendable, Hashable, Identifiable {
  public struct Action: Sendable, Hashable, Identifiable {
    public let label: String
    /// `view`, `http`, `broadcast`, `copy` or the sender's own name.
    public let kind: String
    /// The target when it may be opened (`URLPolicy.openable`); nil otherwise.
    public let url: URL?

    public var id: String { "\(kind)/\(label)/\(url?.absoluteString ?? "")" }
  }

  public struct Attachment: Sendable, Hashable {
    public let name: String
    public let mimeType: String?
    public let size: Int64?
    public let isImage: Bool
    /// The server no longer has the file.
    public let isExpired: Bool
    /// What `AttachmentFetching` takes.
    public let source: MessageAttachment
  }

  public let key: MessageKey
  public let title: String
  /// The sender sent a title; otherwise `title` is the first line of the body.
  public let hasTitle: Bool
  public let body: String
  /// The body is markdown (`content_type: text/markdown`); otherwise show it as plain text.
  public let isMarkdown: Bool
  /// The tag names as sent.
  public let tags: [String]
  /// The tags as emoji where a name is known, else the name itself.
  public let tagLabels: [String]
  public let priority: Priority
  public let time: Date
  public let isRead: Bool
  public let isAcknowledged: Bool
  /// When the message comes back as a reminder.
  public let remindAt: Date?
  /// The click URL, only when `URLPolicy.openable` lets it through.
  public let clickURL: URL?
  public let actions: [Action]
  public let attachment: Attachment?

  public var id: String { "\(key.topic)/\(key.id)" }

  public init(_ stored: StoredMessage, now: Date) {
    let message = stored.message
    let row = MessageRow(stored)
    key = row.key
    title = row.title
    hasTitle = !(message.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    body = message.body
    isMarkdown = message.isMarkdown
    tags = message.tags
    tagLabels = message.tags.map { TagEmoji.emoji(for: $0) ?? $0 }
    priority = message.priority
    time = message.time
    isRead = stored.isRead
    isAcknowledged = stored.isAcknowledged
    remindAt = stored.remindAt
    clickURL = message.click.flatMap(URLPolicy.openable)
    actions = message.actions.map {
      Action(label: $0.label, kind: $0.kind.name, url: $0.url.flatMap(URLPolicy.openable))
    }
    attachment = message.attachment.map { Attachment($0, now: now) }
  }
}

extension MessageDetail.Attachment {
  fileprivate init(_ source: MessageAttachment, now: Date) {
    let fallback = source.url.lastPathComponent
    name = source.name ?? (fallback.isEmpty ? "Attachment" : fallback)
    mimeType = source.mimeType
    size = source.size
    isImage = source.isImage
    isExpired = source.expires.map { $0 <= now } ?? false
    self.source = source
  }
}
