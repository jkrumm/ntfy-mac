import Foundation
import GRDB
import NtfyCore

extension SQLiteHistoryStore: HistoryInbox {
  public func entries(_ query: HistoryQuery) async throws(NtfyError) -> [StoredMessage] {
    guard let select = query.select(server: server) else { return [] }
    return try await fetchStored(select)
  }

  public func message(topic: String, id: String) async throws(NtfyError) -> StoredMessage? {
    var select = HistorySelect(server: server)
    select.and("m.topic = ?", topic)
    select.and("m.id = ?", id)
    select.ordered("m.pk DESC", limit: 1)
    return try await fetchStored(select).first
  }

  public func count(_ query: HistoryQuery) async throws(NtfyError) -> Int {
    guard let select = query.select(server: server, paged: false) else { return 0 }
    return try await read { try select.count($0) }
  }

  public func topics() async throws(NtfyError) -> [TopicSummary] {
    let select = HistorySelect(server: server)
    return try await read { try select.topics($0) }
  }

  public func markUnread(topic: String, id: String) async throws(NtfyError) {
    try await update("read_at = NULL", where: "topic = ? AND id = ?", [topic, id])
  }

  public func markRead(topic: String, id: String) async throws(NtfyError) {
    let now = clock.now()
    try await update(
      "read_at = COALESCE(read_at, ?)", where: "topic = ? AND id = ?", [now, topic, id])
  }

  public func markAllRead(topic: String) async throws(NtfyError) {
    let now = clock.now()
    try await update("read_at = ?", where: "topic = ? AND read_at IS NULL", [now, topic])
  }

  public func acknowledge(topic: String, id: String) async throws(NtfyError) {
    let now = clock.now()
    try await update(
      "read_at = COALESCE(read_at, ?), acked_at = COALESCE(acked_at, ?), remind_at = NULL",
      where: "topic = ? AND id = ?", [now, now, topic, id])
  }

  public func unacknowledged(minPriority: Priority) async throws(NtfyError) -> [StoredMessage] {
    var select = HistorySelect(server: server)
    select.and("m.acked_at IS NULL")
    select.and("m.priority >= ?", minPriority.rawValue)
    select.ordered("m.time ASC, m.pk ASC")
    return try await fetchStored(select)
  }

  public func snooze(topic: String, id: String, until: Date) async throws(NtfyError) {
    try await update("remind_at = ?", where: "topic = ? AND id = ?", [until, topic, id])
  }

  public func clearReminder(topic: String, id: String) async throws(NtfyError) {
    try await update("remind_at = NULL", where: "topic = ? AND id = ?", [topic, id])
  }

  public func dueReminders(now: Date) async throws(NtfyError) -> [StoredMessage] {
    var select = HistorySelect(server: server)
    select.and("m.remind_at <= ?", now)
    select.ordered("m.remind_at ASC, m.pk ASC")
    return try await fetchStored(select)
  }
}
