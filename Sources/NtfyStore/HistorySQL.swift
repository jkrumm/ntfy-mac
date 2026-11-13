import Foundation
import GRDB
import NtfyCore

/// Builds the `SELECT` shared by every read: the newest, non-withdrawn row per sequence.
struct HistorySelect: Sendable {
  private static let visible = """
    m.withdrawn_at IS NULL AND NOT EXISTS (
      SELECT 1 FROM message n
      WHERE n.server = m.server AND n.topic = m.topic AND n.sequence_id = m.sequence_id
        AND (n.time > m.time OR (n.time = m.time AND n.pk > m.pk)))
    """

  private var join = ""
  private var conditions = ["m.server = ?", Self.visible]
  private var arguments: [any DatabaseValueConvertible & Sendable]
  private var tail = ""

  init(server: String) {
    arguments = [server]
  }

  mutating func and(_ condition: String, _ values: any DatabaseValueConvertible & Sendable...) {
    conditions.append(condition)
    arguments.append(contentsOf: values)
  }

  mutating func matching(_ pattern: FTS5Pattern) {
    join = "JOIN message_ft ON message_ft.rowid = m.pk"
    and("message_ft MATCH ?", pattern)
  }

  /// `order` is trusted SQL, never user input.
  mutating func ordered(_ order: String, limit: Int? = nil, offset: Int = 0) {
    tail = "ORDER BY \(order)"
    guard let limit else { return }
    tail += " LIMIT \(max(limit, 0)) OFFSET \(max(offset, 0))"
  }

  func count(_ database: Database) throws -> Int {
    let sql =
      "SELECT COUNT(*) FROM message m \(join) WHERE \(conditions.joined(separator: " AND "))"
    return try Int.fetchOne(database, sql: sql, arguments: StatementArguments(arguments)) ?? 0
  }

  func topics(_ database: Database) throws -> [TopicSummary] {
    let sql = """
      SELECT m.topic AS topic, COUNT(*) AS total, SUM(m.read_at IS NULL) AS unread,
        MAX(m.time) AS newest
      FROM message m \(join) WHERE \(conditions.joined(separator: " AND "))
      GROUP BY m.topic ORDER BY newest DESC, m.topic ASC
      """
    return try Row.fetchAll(database, sql: sql, arguments: StatementArguments(arguments)).map {
      TopicSummary(
        topic: $0["topic"], total: $0["total"], unread: $0["unread"], newest: $0["newest"])
    }
  }

  func fetch(_ database: Database) throws -> [MessageRecord] {
    let sql =
      "SELECT m.* FROM message m \(join) WHERE \(conditions.joined(separator: " AND ")) \(tail)"
    return try MessageRecord.fetchAll(database, sql: sql, arguments: StatementArguments(arguments))
  }
}

extension HistoryQuery {
  /// The select for these filters, or `nil` when the text yields no searchable word.
  func select(server: String, paged: Bool = true) -> HistorySelect? {
    var select = HistorySelect(server: server)
    if let topic { select.and("m.topic = ?", topic) }
    if unreadOnly { select.and("m.read_at IS NULL") }
    if let unacknowledgedFrom {
      select.and("m.acked_at IS NULL")
      select.and("m.priority >= ?", unacknowledgedFrom.rawValue)
    }
    if let minPriority { select.and("m.priority >= ?", minPriority.rawValue) }
    if let since { select.and("m.time >= ?", since) }
    if let until { select.and("m.time <= ?", until) }
    if let text {
      guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return nil }
      select.matching(pattern)
    }
    if paged { select.ordered("m.time DESC, m.pk DESC", limit: limit, offset: offset) }
    return select
  }
}
