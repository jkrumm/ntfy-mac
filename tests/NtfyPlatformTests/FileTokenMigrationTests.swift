import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

private actor MemorySecrets: SecretStore {
  private var stored: String?
  func token() -> String? { stored }
  func setToken(_ token: String) { stored = token }
  func deleteToken() { stored = nil }
}

private struct RefusingSecrets: SecretStore {
  func token() -> String? { nil }
  func setToken(_ token: String) throws(NtfyError) { throw .permissionDenied }
  func deleteToken() {}
}

/// The migration against the real file store: only `token` leaves the file.
@Suite struct FileTokenMigrationTests {
  private let legacy =
    #"{"url":"https://n.example.com","token":"tk","unknown":[1],"extraTopics":["a"]}"#

  @Test func scrubsOnlyTheTokenKey() async throws {
    let dir = TempDirectory()
    try dir.write(legacy, to: "config.json")
    let store = FileConfigStore(url: dir.file("config.json"))
    let secrets = MemorySecrets()
    #expect(try await ConfigTokenMigration(config: store, secrets: secrets).run() == .migrated)
    #expect(await secrets.token() == "tk")
    let object = try #require(ConfigValue.parseObject(Data(dir.read("config.json").utf8)))
    #expect(object["token"] == nil)
    #expect(object["unknown"] == .array([.int(1)]))
    #expect(object["url"] == .string("https://n.example.com"))
    #expect(object["extraTopics"] == .array([.string("a")]))
    #expect(
      try await ConfigTokenMigration(config: store, secrets: secrets).run() == .alreadyMigrated)
  }

  @Test func aRefusingSecretStoreLeavesTheFileByteForByte() async throws {
    let dir = TempDirectory()
    try dir.write(legacy, to: "config.json")
    let migration = ConfigTokenMigration(
      config: FileConfigStore(url: dir.file("config.json")), secrets: RefusingSecrets())
    await #expect(throws: NtfyError.permissionDenied) { try await migration.run() }
    #expect(try dir.read("config.json") == legacy)
  }

  @Test func aMalformedFileIsNotTouched() async throws {
    let dir = TempDirectory()
    try dir.write("{ broken", to: "config.json")
    let migration = ConfigTokenMigration(
      config: FileConfigStore(url: dir.file("config.json")), secrets: MemorySecrets())
    #expect(try await migration.run() == .nothingToMigrate)
    #expect(try dir.read("config.json") == "{ broken")
  }

  @Test func aWhitespaceOnlyTokenLeavesTheFileByteForByte() async throws {
    let dir = TempDirectory()
    let content = #"{"url":"https://n.example.com","token":"   ","unknown":true}"#
    try dir.write(content, to: "config.json")
    let secrets = MemorySecrets()
    let migration = ConfigTokenMigration(
      config: FileConfigStore(url: dir.file("config.json")), secrets: secrets)
    #expect(try await migration.run() == .nothingToMigrate)
    #expect(try dir.read("config.json") == content)
    #expect(await secrets.token() == nil)
  }
}
