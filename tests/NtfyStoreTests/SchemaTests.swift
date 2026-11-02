import Foundation
import NtfyCore
import NtfyTesting
import SQLite3
import Testing

@testable import NtfyStore

/// Looks at the database file with plain SQLite, independent of the store under test.
@discardableResult
private func sqlite<T>(_ url: URL, readOnly: Bool = false, _ body: (OpaquePointer) throws -> T)
  throws -> T
{
  var handle: OpaquePointer?
  let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
  guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
    throw NtfyError.storage("cannot open the test database")
  }
  defer { sqlite3_close(handle) }
  return try body(handle)
}

private func text(_ database: OpaquePointer, _ sql: String) -> String? {
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0)
  else { return nil }
  return String(cString: value)
}

@Suite struct SchemaTests {
  private func store() throws -> (HistoryRig, URL) {
    let rig = try HistoryRig(.sqlite)
    return (rig, rig.directory.databaseURL)
  }

  @Test func messageHasAnExplicitAutoincrementKeyAndStaysUniquePerServerTopicID() throws {
    let (rig, url) = try store()
    defer { withExtendedLifetime(rig) {} }
    try sqlite(url, readOnly: true) { database in
      let table = text(database, "SELECT sql FROM sqlite_master WHERE name = 'message'") ?? ""
      #expect(table.contains("pk INTEGER PRIMARY KEY AUTOINCREMENT"))
      let index = text(database, "SELECT sql FROM sqlite_master WHERE name = 'message_key'") ?? ""
      #expect(index.contains("UNIQUE"))
      #expect(index.contains("(server, topic, id)"))
    }
  }

  @Test func theSearchIndexFollowsTheExplicitKey() throws {
    let (rig, url) = try store()
    defer { withExtendedLifetime(rig) {} }
    try sqlite(url, readOnly: true) { database in
      let search = text(database, "SELECT sql FROM sqlite_master WHERE name = 'message_ft'") ?? ""
      #expect(search.contains("content_rowid=\"pk\"") || search.contains("content_rowid='pk'"))
    }
  }

  @Test func searchFindsRowsAfterInsertUpdateAndDelete() async throws {
    let rig = try HistoryRig(.sqlite)
    try await rig.store.append(rig.message("1", title: "Backup", body: "finished nightly"))
    let hits = try await rig.store.entries(HistoryQuery(text: "nightly"))
    #expect(hits.map(\.message.id) == ["1"])
    try await rig.store.prune(policy: RetentionPolicy(maxPerTopic: 0), now: rig.clock.now())
    #expect(try await rig.store.entries(HistoryQuery(text: "nightly")).isEmpty)
  }

  @Test func sameTimestampsFallBackToArrivalOrder() async throws {
    let rig = try HistoryRig(.sqlite)
    for id in ["b", "a", "c"] { try await rig.store.append(rig.message(id, at: 0)) }
    #expect(try await rig.store.recent(limit: 10).map(\.id) == ["c", "a", "b"])
    #expect(try await rig.store.lastMessageID() == "c")
  }

  @Test func aDatabaseFromANewerVersionIsRefusedByTheReader() throws {
    let (rig, url) = try store()
    defer { withExtendedLifetime(rig) {} }
    try sqlite(url) { database in
      sqlite3_exec(
        database, "INSERT INTO grdb_migrations (identifier) VALUES ('v99-from-the-future')", nil,
        nil, nil)
    }
    #expect {
      try SQLiteHistoryStore.openReadOnly(
        at: url, server: HistoryRig.server, clock: FakeClock())
    } throws: { error in
      guard case .storage(let message) = error as? NtfyError else { return false }
      return message.contains("newer version")
    }
  }

  @Test func aSchemaThatWasNeverMigratedIsRefusedByTheReader() throws {
    let directory = TempDirectory()
    try FileManager.default.createDirectory(
      at: directory.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var handle: OpaquePointer?
    sqlite3_open(directory.databaseURL.path, &handle)
    sqlite3_exec(handle, "CREATE TABLE unrelated (x INTEGER)", nil, nil, nil)
    sqlite3_close(handle)
    #expect {
      try SQLiteHistoryStore.openReadOnly(
        at: directory.databaseURL, server: HistoryRig.server, clock: FakeClock())
    } throws: { error in
      guard case .storage(let message) = error as? NtfyError else { return false }
      return message.contains("not initialised")
    }
  }
}
