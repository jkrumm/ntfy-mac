import Foundation
import NtfyCore

/// Keeps history in memory with the same observable contract as the SQLite store.
public actor InMemoryHistoryStore: HistoryStore, HistoryInbox, HistoryObserving {
  struct Row {
    var stored: StoredMessage
    var sequenceID: String
    var withdrawn = false
  }

  var rows: [Row] = []
  let clock: any NtfyCore.Clock
  private let signal = ChangeSignal()
  private var appendFailure: NtfyError?
  private var appendsBeforeFailure = 0
  private var clearReminderFailure: NtfyError?
  private var afterEntries: (@Sendable (HistoryQuery) async -> Void)?

  public init(clock: any NtfyCore.Clock = FakeClock()) {
    self.clock = clock
  }

  /// Fires after every mutation, like the SQLite store.
  public nonisolated func changes() -> AsyncStream<Void> { signal.stream() }

  /// Makes `append` throw `failure` once `successes` more appends went through, or work again
  /// with `nil`.
  public func setAppendFailure(_ failure: NtfyError?, afterSuccesses successes: Int = 0) {
    appendFailure = failure
    appendsBeforeFailure = successes
  }

  /// Runs `hook` after each `entries` read has taken its snapshot, before it returns: a message
  /// arriving between two pages of a read.
  public func setAfterEntries(_ hook: (@Sendable (HistoryQuery) async -> Void)?) {
    afterEntries = hook
  }

  /// Makes `clearReminder` throw `failure`, or work again with `nil`.
  public func setClearReminderFailure(_ failure: NtfyError?) {
    clearReminderFailure = failure
  }

  @discardableResult
  public func append(_ message: NtfyMessage) throws(NtfyError) -> Bool {
    if let appendFailure {
      if appendsBeforeFailure == 0 { throw appendFailure }
      appendsBeforeFailure -= 1
    }
    if rows.contains(where: {
      $0.stored.message.topic == message.topic && $0.stored.message.id == message.id
    }) {
      return false
    }
    rows.append(
      Row(stored: StoredMessage(message: message), sequenceID: message.sequenceID ?? message.id))
    signal.fire()
    return true
  }

  public func recent(limit: Int) -> [NtfyMessage] {
    Array(visible().reversed().prefix(max(limit, 0))).map(\.stored.message)
  }

  public func lastMessageID() -> String? { rows.last?.stored.message.id }

  public func markNotified(topic: String, id: String, at time: Date) {
    change(topic: topic, id: id) { $0.notifiedAt = $0.notifiedAt ?? time }
  }

  public func unnotified(limit: Int, offset: Int) -> [NtfyMessage] {
    let pending = visible().filter { $0.stored.notifiedAt == nil }
    return Array(pending.dropFirst(max(offset, 0)).prefix(max(limit, 0))).map(\.stored.message)
  }

  public func withdraw(topic: String, sequenceID: String) {
    for index in rows.indices where rows[index].matches(topic: topic, sequenceID: sequenceID) {
      rows[index].withdrawn = true
    }
    signal.fire()
  }

  public func markCleared(topic: String, sequenceID: String) {
    let now = clock.now()
    for index in rows.indices where rows[index].matches(topic: topic, sequenceID: sequenceID) {
      rows[index].stored.settle(at: now)
    }
    signal.fire()
  }

  @discardableResult
  public func prune(policy: RetentionPolicy, now: Date) -> Int {
    let cutoff = now.addingTimeInterval(-policy.maxAge)
    var kept: [Row] = []
    var perTopic: [String: Int] = [:]
    for row in rows.reversed() {
      let topic = row.stored.message.topic
      let count = perTopic[topic, default: 0]
      guard row.stored.message.time >= cutoff, count < max(policy.maxPerTopic, 0) else { continue }
      perTopic[topic] = count + 1
      kept.append(row)
    }
    let removed = rows.count - kept.count
    rows = kept.reversed()
    if removed > 0 { signal.fire() }
    return removed
  }

  /// Oldest first: not withdrawn, and not superseded by a newer row of the same sequence.
  func visible() -> [Row] {
    let ordered = rows.enumerated().sorted {
      ($0.element.time, $0.offset) < ($1.element.time, $1.offset)
    }
    var seen = Set<[String]>()
    var result: [Row] = []
    for row in ordered.reversed().map(\.element) {
      let isNewest = seen.insert([row.topic, row.sequenceID]).inserted
      if isNewest, !row.withdrawn { result.append(row) }
    }
    return result.reversed()
  }

  func change(topic: String, id: String, _ edit: (inout StoredMessage) -> Void) {
    for index in rows.indices
    where rows[index].stored.message.topic == topic && rows[index].stored.message.id == id {
      edit(&rows[index].stored)
    }
    signal.fire()
  }
}

extension InMemoryHistoryStore.Row {
  var topic: String { stored.message.topic }
  var time: Date { stored.message.time }

  fileprivate func matches(topic: String, sequenceID: String) -> Bool {
    self.topic == topic && self.sequenceID == sequenceID
  }
}

extension StoredMessage {
  /// Read, acknowledged and no longer to be reminded of.
  mutating func settle(at now: Date) {
    readAt = readAt ?? now
    ackedAt = ackedAt ?? now
    remindAt = nil
  }
}

extension InMemoryHistoryStore {
  public func entries(_ query: HistoryQuery) async -> [StoredMessage] {
    let words = SearchWords(query.text)
    guard words.isSearchable else { return [] }
    let matches = visible().map(\.stored).filter { query.accepts($0) && words.match($0.message) }
    let page = Array(matches.reversed().dropFirst(max(query.offset, 0)).prefix(max(query.limit, 0)))
    await afterEntries?(query)
    return page
  }

  public func message(topic: String, id: String) -> StoredMessage? {
    visible().map(\.stored).first { $0.message.topic == topic && $0.message.id == id }
  }

  public func count(_ query: HistoryQuery) -> Int {
    let words = SearchWords(query.text)
    guard words.isSearchable else { return 0 }
    return visible().map(\.stored).filter { query.accepts($0) && words.match($0.message) }.count
  }

  public func topics() -> [TopicSummary] {
    let grouped = Dictionary(grouping: visible().map(\.stored), by: { $0.message.topic })
    return grouped.map { topic, entries in
      TopicSummary(
        topic: topic, total: entries.count, unread: entries.filter { !$0.isRead }.count,
        newest: entries.map(\.message.time).max() ?? .distantPast)
    }.sorted { ($1.newest, $0.topic) < ($0.newest, $1.topic) }
  }

  public func markUnread(topic: String, id: String) {
    change(topic: topic, id: id) { $0.readAt = nil }
  }

  public func markRead(topic: String, id: String) {
    let now = clock.now()
    change(topic: topic, id: id) { $0.readAt = $0.readAt ?? now }
  }

  public func markAllRead(topic: String) {
    let now = clock.now()
    for index in rows.indices where rows[index].topic == topic {
      rows[index].stored.readAt = rows[index].stored.readAt ?? now
    }
    signal.fire()
  }

  public func acknowledge(topic: String, id: String) {
    let now = clock.now()
    change(topic: topic, id: id) { $0.settle(at: now) }
  }

  public func unacknowledged(minPriority: Priority) -> [StoredMessage] {
    visible().map(\.stored).filter { $0.ackedAt == nil && $0.message.priority >= minPriority }
  }

  public func snooze(topic: String, id: String, until: Date) {
    change(topic: topic, id: id) { $0.remindAt = until }
  }

  public func clearReminder(topic: String, id: String) throws(NtfyError) {
    if let clearReminderFailure { throw clearReminderFailure }
    change(topic: topic, id: id) { $0.remindAt = nil }
  }

  public func dueReminders(now: Date) -> [StoredMessage] {
    visible().map(\.stored)
      .filter { ($0.remindAt ?? .distantFuture) <= now }
      .sorted { ($0.remindAt ?? .distantFuture) < ($1.remindAt ?? .distantFuture) }
  }
}

extension HistoryQuery {
  fileprivate func accepts(_ stored: StoredMessage) -> Bool {
    if let topic, stored.message.topic != topic { return false }
    if unreadOnly, stored.readAt != nil { return false }
    if let unacknowledgedFrom,
      stored.ackedAt != nil || stored.message.priority < unacknowledgedFrom
    {
      return false
    }
    if let minPriority, stored.message.priority < minPriority { return false }
    if let since, stored.message.time < since { return false }
    if let until, stored.message.time > until { return false }
    return true
  }
}

/// A stand-in for the SQLite full-text match: every word of the query must start a word of the
/// title or body, case-insensitively.
private struct SearchWords {
  let words: [String]
  let isSearchable: Bool

  init(_ text: String?) {
    guard let text else {
      words = []
      isSearchable = true
      return
    }
    words = Self.split(text)
    isSearchable = !words.isEmpty
  }

  func match(_ message: NtfyMessage) -> Bool {
    let haystack = Self.split("\(message.title ?? "") \(message.body)")
    return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
  }

  private static func split(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
  }
}
