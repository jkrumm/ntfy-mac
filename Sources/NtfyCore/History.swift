import Foundation

/// A stored message together with what the user and the delivery layer did with it.
public struct StoredMessage: Sendable, Hashable {
  public var message: NtfyMessage
  public var readAt: Date?
  public var ackedAt: Date?
  public var notifiedAt: Date?
  public var remindAt: Date?

  public init(
    message: NtfyMessage, readAt: Date? = nil, ackedAt: Date? = nil, notifiedAt: Date? = nil,
    remindAt: Date? = nil
  ) {
    self.message = message
    self.readAt = readAt
    self.ackedAt = ackedAt
    self.notifiedAt = notifiedAt
    self.remindAt = remindAt
  }

  public var isRead: Bool { readAt != nil }
  public var isAcknowledged: Bool { ackedAt != nil }
}

/// Filters for browsing history. Every field narrows the result; the default matches everything.
public struct HistoryQuery: Sendable, Hashable {
  public var topic: String?
  public var unreadOnly: Bool
  /// Free text over title and body; each word matches as a prefix.
  public var text: String?
  public var minPriority: Priority?
  public var since: Date?
  /// Only messages at or before this time; pins a multi-page read against messages arriving.
  public var until: Date?
  public var limit: Int
  public var offset: Int

  public init(
    topic: String? = nil, unreadOnly: Bool = false, text: String? = nil,
    minPriority: Priority? = nil, since: Date? = nil, until: Date? = nil, limit: Int = 100,
    offset: Int = 0
  ) {
    self.topic = topic
    self.unreadOnly = unreadOnly
    self.text = text
    self.minPriority = minPriority
    self.since = since
    self.until = until
    self.limit = limit
    self.offset = offset
  }
}

/// One topic as the sidebar of the History window shows it.
public struct TopicSummary: Sendable, Hashable, Identifiable {
  public let topic: String
  /// Visible messages (not withdrawn, newest of their sequence).
  public let total: Int
  public let unread: Int
  /// Time of the newest message.
  public let newest: Date

  public var id: String { topic }

  public init(topic: String, total: Int, unread: Int, newest: Date) {
    self.topic = topic
    self.total = total
    self.unread = unread
    self.newest = newest
  }
}

/// How much history is kept: the newest `maxPerTopic` rows per topic, none older than `maxAge`.
public struct RetentionPolicy: Sendable, Hashable {
  public var maxPerTopic: Int
  public var maxAge: TimeInterval

  public init(maxPerTopic: Int = 1000, maxAge: TimeInterval = 90 * 24 * 60 * 60) {
    self.maxPerTopic = maxPerTopic
    self.maxAge = maxAge
  }
}
