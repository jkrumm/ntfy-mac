import Foundation
import NtfyCore

/// The round picture of a conversation: the topic's first known emoji tag, else its initial, on a
/// colour that depends on the topic name alone.
public struct ConversationAvatar: Sendable, Hashable {
  /// How many colours the view's palette holds; `colorIndex` is always below it.
  public static let paletteSize = 8

  /// An emoji or one uppercase letter.
  public let glyph: String
  public let isEmoji: Bool
  public let colorIndex: Int

  /// `tags` are the tag lists of the topic's newest messages, newest first.
  public init(topic: String, tags: [[String]]) {
    let emoji = tags.lazy.flatMap { $0 }.compactMap(TagEmoji.emoji(for:)).first
    if let emoji {
      glyph = emoji
      isEmoji = true
    } else {
      glyph = Self.initial(of: topic)
      isEmoji = false
    }
    colorIndex = Self.colorIndex(forTopic: topic)
  }

  /// FNV-1a over the UTF-8 bytes. `Hasher` is seeded per process, so it cannot colour a topic
  /// the same way twice.
  public static func colorIndex(forTopic topic: String) -> Int {
    var hash: UInt32 = 2_166_136_261
    for byte in topic.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 16_777_619
    }
    return Int(hash % UInt32(paletteSize))
  }

  static func initial(of topic: String) -> String {
    topic.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "#"
  }
}

/// One topic as the sidebar shows it: a conversation.
public struct Conversation: Sendable, Hashable, Identifiable {
  public let topic: String
  public let avatar: ConversationAvatar
  /// One line: the newest message's body (its title when it has none), "You: " in front of a
  /// message this app published.
  public let preview: String
  /// When the newest message arrived.
  public let time: Date
  public let unread: Int
  /// An unacknowledged message of high or urgent priority is waiting.
  public let hasUrgent: Bool

  public var id: String { topic }

  public init(
    topic: String, avatar: ConversationAvatar, preview: String, time: Date, unread: Int,
    hasUrgent: Bool
  ) {
    self.topic = topic
    self.avatar = avatar
    self.preview = preview
    self.time = time
    self.unread = unread
    self.hasUrgent = hasUrgent
  }

  /// Newest activity first; equal times by name, so the order never flickers.
  static func ordered(_ conversations: [Conversation]) -> [Conversation] {
    conversations.sorted { ($1.time, $0.topic) < ($0.time, $1.topic) }
  }

  /// The one-line preview of a message.
  static func preview(of message: NtfyMessage, isOwn: Bool) -> String {
    let body = message.body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let text = (body.isEmpty ? title : body).trimmingCharacters(in: .whitespaces)
    return isOwn ? "You: \(text)" : text
  }
}
