import Foundation
import GRDB
import NtfyCore

extension SQLiteHistoryStore: HistoryInbox {
  public func entries(_ query: HistoryQuery) async throws(NtfyError) -> [StoredMessage] {
    guard let select = query.select(server: server) else { return [] }
    return try await fetchStored(select)
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
    select.ordered("m.time ASC, m.rowid ASC")
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
    select.ordered("m.remind_at ASC, m.rowid ASC")
    return try await fetchStored(select)
  }
}
