import Foundation
import NtfyCore
import NtfyStore
import NtfyTesting
import Testing

/// Behaviour only the SQLite store has: files, modes, processes and schema.
@Suite struct SQLiteHistoryStoreTests {
  private func reopen(_ rig: HistoryRig, server: String = HistoryRig.server) throws
    -> SQLiteHistoryStore
  {
    try SQLiteHistoryStore.open(at: rig.directory.databaseURL, server: server, clock: rig.clock)
  }

  @Test func reopeningKeepsDataAndMigratesOnlyOnce() async throws {
    let rig = try HistoryRig(.sqlite)
    try await rig.store.append(rig.message("1", body: "kept"))
    let second = try reopen(rig)
    #expect(try await second.recent(limit: 10).map(\.id) == ["1"])
    #expect(try await second.append(rig.message("1")) == false)
    #expect(try await second.entries(HistoryQuery(text: "kept")).count == 1)
  }

  @Test func serversDoNotShareHistory() async throws {
    let rig = try HistoryRig(.sqlite)
    try await rig.store.append(rig.message("1"))
    let other = try reopen(rig, server: "https://other.example.com")
    #expect(try await other.recent(limit: 10).isEmpty)
    #expect(try await other.lastMessageID() == nil)
    #expect(try await other.append(rig.message("1")) == true)
  }

  @Test func readOnlyPoolSeesCommittedWritesAndRefusesWrites() async throws {
    let rig = try HistoryRig(.sqlite)
    try await rig.store.append(rig.message("1"))
    let reader = try SQLiteHistoryStore.openReadOnly(
      at: rig.directory.databaseURL, server: HistoryRig.server, clock: rig.clock)
    #expect(try await reader.recent(limit: 10).map(\.id) == ["1"])

    try await rig.store.append(rig.message("2", at: 1))
    #expect(try await reader.recent(limit: 10).map(\.id) == ["2", "1"])
    #expect(try await reader.entries(HistoryQuery(text: "body")).count == 2)

    await #expect {
      try await reader.append(rig.message("3", at: 2))
    } throws: { error in
      guard case .storage = error as? NtfyError else { return false }
      return true
    }
    #expect(try await reader.recent(limit: 10).count == 2)
  }

  @Test func readOnlyOpenFailsWithoutAnInitialisedDatabase() throws {
    let directory = TempDirectory()
    let clock = FakeClock()
    #expect(throws: NtfyError.self) {
      try SQLiteHistoryStore.openReadOnly(
        at: directory.databaseURL, server: HistoryRig.server, clock: clock)
    }
    try FileManager.default.createDirectory(
      at: directory.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: directory.databaseURL.path, contents: nil)
    #expect(throws: NtfyError.self) {
      try SQLiteHistoryStore.openReadOnly(
        at: directory.databaseURL, server: HistoryRig.server, clock: clock)
    }
  }

  @Test func databaseAndDirectoryArePrivate() async throws {
    let rig = try HistoryRig(.sqlite)
    try await rig.store.append(rig.message("1"))
    let file = rig.directory.databaseURL
    #expect(try rig.directory.permissions(file) == 0o600)
    #expect(try rig.directory.permissions(file.deletingLastPathComponent()) == 0o700)
    for suffix in ["-wal", "-shm"] {
      let sidecar = URL(fileURLWithPath: file.path + suffix)
      #expect(try rig.directory.permissions(sidecar) == 0o600)
    }
  }

  @Test func existingLooseModesAreTightened() throws {
    let rig = TempDirectory()
    let directory = rig.databaseURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    FileManager.default.createFile(
      atPath: rig.databaseURL.path, contents: nil, attributes: [.posixPermissions: 0o644])
    _ = try SQLiteHistoryStore.open(
      at: rig.databaseURL, server: HistoryRig.server, clock: FakeClock())
    #expect(try rig.permissions(rig.databaseURL) == 0o600)
    #expect(try rig.permissions(directory) == 0o700)
  }

  @Test func closedStoreRefusesFurtherUse() async throws {
    let rig = try HistoryRig(.sqlite)
    let store = try SQLiteHistoryStore.open(
      at: rig.directory.databaseURL, server: HistoryRig.server, clock: rig.clock)
    try await store.append(rig.message("1"))
    try store.close()
    await #expect(throws: NtfyError.self) { try await store.recent(limit: 1) }
  }
}
