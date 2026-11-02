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
  public var limit: Int
  public var offset: Int

  public init(
    topic: String? = nil, unreadOnly: Bool = false, text: String? = nil,
    minPriority: Priority? = nil, since: Date? = nil, limit: Int = 100, offset: Int = 0
  ) {
    self.topic = topic
    self.unreadOnly = unreadOnly
    self.text = text
    self.minPriority = minPriority
    self.since = since
    self.limit = limit
    self.offset = offset
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
