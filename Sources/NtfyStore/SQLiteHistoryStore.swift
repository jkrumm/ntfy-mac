import Foundation
import GRDB
import NtfyCore

/// History in a SQLite file (WAL). The app opens it as the single writer; the CLI opens the same
/// file read-only. Every row carries the `server` origin it was received from.
public final class SQLiteHistoryStore: HistoryStore, HistoryObserving, Sendable {
  let pool: DatabasePool
  private let signal = ChangeSignal()
  let server: String
  let clock: any NtfyCore.Clock

  private init(pool: DatabasePool, server: String, clock: any NtfyCore.Clock) {
    self.pool = pool
    self.server = server
    self.clock = clock
  }

  /// Creates and migrates the database when needed.
  public static func open(
    at url: URL, server: String, clock: any NtfyCore.Clock
  ) throws(NtfyError) -> SQLiteHistoryStore {
    SQLiteHistoryStore(pool: try HistoryDatabase.openWriter(at: url), server: server, clock: clock)
  }

  /// For processes that must not write; every mutation fails with `.storage`.
  public static func openReadOnly(
    at url: URL, server: String, clock: any NtfyCore.Clock
  ) throws(NtfyError) -> SQLiteHistoryStore {
    SQLiteHistoryStore(pool: try HistoryDatabase.openReader(at: url), server: server, clock: clock)
  }

  /// Closes the database connections. Every later call fails with `.storage`. Call it only after
  /// everything that uses the store has stopped.
  public func close() throws(NtfyError) {
    do {
      try pool.close()
    } catch {
      throw HistoryError.map(error)
    }
  }

  @discardableResult
  public func append(_ message: NtfyMessage) async throws(NtfyError) -> Bool {
    let server = server
    let now = clock.now()
    let inserted = try await write { database in
      try MessageRecord(message, server: server, createdAt: now).insert(
        database, onConflict: .ignore)
      return database.changesCount == 1
    }
    if inserted { signal.fire() }
    return inserted
  }

  /// Fires after every committed write made through this object.
  public func changes() -> AsyncStream<Void> { signal.stream() }

  public func recent(limit: Int) async throws(NtfyError) -> [NtfyMessage] {
    var select = HistorySelect(server: server)
    select.ordered("m.time DESC, m.pk DESC", limit: limit)
    return try await fetchMessages(select)
  }

  public func lastMessageID() async throws(NtfyError) -> String? {
    let server = server
    return try await read { database in
      try String.fetchOne(
        database, sql: "SELECT id FROM message WHERE server = ? ORDER BY pk DESC LIMIT 1",
        arguments: [server])
    }
  }

  public func markNotified(topic: String, id: String, at time: Date) async throws(NtfyError) {
    try await update(
      "notified_at = COALESCE(notified_at, ?)", where: "topic = ? AND id = ?", [time, topic, id])
  }

  public func unnotified(limit: Int, offset: Int) async throws(NtfyError) -> [NtfyMessage] {
    var select = HistorySelect(server: server)
    select.and("m.notified_at IS NULL")
    select.ordered("m.time ASC, m.pk ASC", limit: limit, offset: offset)
    return try await fetchMessages(select)
  }

  public func withdraw(topic: String, sequenceID: String) async throws(NtfyError) {
    let now = clock.now()
    try await update(
      "withdrawn_at = COALESCE(withdrawn_at, ?)", where: "topic = ? AND sequence_id = ?",
      [now, topic, sequenceID])
  }

  public func markCleared(topic: String, sequenceID: String) async throws(NtfyError) {
    let now = clock.now()
    try await update(
      "read_at = COALESCE(read_at, ?), acked_at = COALESCE(acked_at, ?), remind_at = NULL",
      where: "topic = ? AND sequence_id = ?", [now, now, topic, sequenceID])
  }

  @discardableResult
  public func prune(policy: RetentionPolicy, now: Date) async throws(NtfyError) -> Int {
    let server = server
    let cutoff = now.addingTimeInterval(-policy.maxAge)
    let dropped = try await write { database in
      try database.execute(
        sql: """
          DELETE FROM message WHERE server = ? AND (time < ? OR pk IN (
            SELECT pk FROM (
              SELECT pk, ROW_NUMBER() OVER (
                PARTITION BY topic ORDER BY time DESC, pk DESC) AS position
              FROM message WHERE server = ?)
            WHERE position > ?))
          """,
        arguments: [server, cutoff, server, max(policy.maxPerTopic, 0)])
      return database.changesCount
    }
    if dropped > 0 { signal.fire() }
    return dropped
  }
}

extension SQLiteHistoryStore {
  func read<T: Sendable>(
    _ body: @escaping @Sendable (Database) throws -> T
  ) async throws(NtfyError) -> T {
    do { return try await pool.read(body) } catch { throw HistoryError.map(error) }
  }

  func write<T: Sendable>(
    _ body: @escaping @Sendable (Database) throws -> T
  ) async throws(NtfyError) -> T {
    do { return try await pool.write(body) } catch { throw HistoryError.map(error) }
  }

  func fetchMessages(_ select: HistorySelect) async throws(NtfyError) -> [NtfyMessage] {
    try await read { try select.fetch($0).map { try $0.message() } }
  }

  func fetchStored(_ select: HistorySelect) async throws(NtfyError) -> [StoredMessage] {
    try await read { try select.fetch($0).map { try $0.stored() } }
  }

  /// `UPDATE message SET <assignments> WHERE server = ? AND <condition>`; `values` fill the
  /// placeholders of `assignments`, then of `condition`. Both strings are trusted SQL.
  func update(
    _ assignments: String, where condition: String,
    _ values: [any DatabaseValueConvertible & Sendable]
  ) async throws(NtfyError) {
    let server = server
    let sql = "UPDATE message SET \(assignments) WHERE server = ? AND \(condition)"
    let leading = assignments.filter { $0 == "?" }.count
    let arguments = Array(values[..<leading]) + [server] + Array(values[leading...])
    try await write { database in
      try database.execute(sql: sql, arguments: StatementArguments(arguments))
    }
    signal.fire()
  }
}
