import Testing

@testable import NtfyCore
@testable import NtfyTesting

private actor FailingSecretStore: SecretStore {
  func token() throws(NtfyError) -> String? { nil }
  func setToken(_ token: String) throws(NtfyError) { throw .permissionDenied }
  func deleteToken() throws(NtfyError) {}
}

/// Accepts the write but reads back something else.
private actor LossySecretStore: SecretStore {
  func token() -> String? { nil }
  func setToken(_ token: String) {}
  func deleteToken() {}
}

/// Writes to the config while the secret store write is in flight, like another process would.
private actor RacingSecretStore: SecretStore {
  private var stored: String?
  private let config: InMemoryConfigStore
  private let racingChange: @Sendable (inout Config) -> Void

  init(config: InMemoryConfigStore, racingChange: @escaping @Sendable (inout Config) -> Void) {
    self.config = config
    self.racingChange = racingChange
  }

  func token() -> String? { stored }
  func setToken(_ token: String) async {
    await config.update(racingChange)
    stored = token
  }
  func deleteToken() { stored = nil }
}

/// A config store whose atomic update always fails.
private struct UpdateFailingConfigStore: ConfigStore {
  let base: InMemoryConfigStore
  func load() async -> Config { await base.load() }
  func save(_ config: Config) async { await base.save(config) }
  func update(_ change: @Sendable (inout Config) -> Void) async throws(NtfyError) {
    throw .storage("disk full")
  }
}

@Suite struct ConfigTokenMigrationTests {
  private let extras: [String: ConfigValue] = ["keep": .string("me")]

  @Test func movesTheTokenAndKeepsEverythingElse() async throws {
    let config = InMemoryConfigStore(
      Config(url: "https://n.example.com", token: " tok ", extraTopics: ["a"], extras: extras))
    let secrets = InMemorySecretStore()
    let outcome = try await ConfigTokenMigration(config: config, secrets: secrets).run()
    #expect(outcome == .migrated)
    #expect(await secrets.token() == "tok")
    #expect(
      await config.load()
        == Config(url: "https://n.example.com", extraTopics: ["a"], extras: extras))
  }

  @Test func isIdempotent() async throws {
    let config = InMemoryConfigStore(Config(token: "tok"))
    let secrets = InMemorySecretStore()
    let migration = ConfigTokenMigration(config: config, secrets: secrets)
    #expect(try await migration.run() == .migrated)
    #expect(try await migration.run() == .alreadyMigrated)
    #expect(await secrets.token() == "tok")
    #expect(await config.load().token == nil)
  }

  @Test func theKeychainWinsAndThePlaintextIsStillScrubbed() async throws {
    let config = InMemoryConfigStore(Config(token: "old", extras: extras))
    let secrets = InMemorySecretStore(token: "new")
    let outcome = try await ConfigTokenMigration(config: config, secrets: secrets).run()
    #expect(outcome == .alreadyMigrated)
    #expect(await secrets.token() == "new")
    #expect(await config.load() == Config(extras: extras))
  }

  @Test func nothingToMigrate() async throws {
    let config = InMemoryConfigStore(Config(url: "https://n.example.com", token: "  "))
    let outcome = try await ConfigTokenMigration(config: config, secrets: InMemorySecretStore())
      .run()
    #expect(outcome == .nothingToMigrate)
  }

  @Test func aFailingSecretStoreLeavesTheFileUntouched() async throws {
    let original = Config(token: "only-copy", extras: extras)
    let config = InMemoryConfigStore(original)
    let migration = ConfigTokenMigration(config: config, secrets: FailingSecretStore())
    await #expect(throws: NtfyError.permissionDenied) { try await migration.run() }
    #expect(await config.load() == original)
  }

  @Test func aStoreThatDoesNotReadBackLeavesTheFileUntouched() async throws {
    let original = Config(token: "only-copy")
    let config = InMemoryConfigStore(original)
    let migration = ConfigTokenMigration(config: config, secrets: LossySecretStore())
    await #expect(throws: NtfyError.self) { try await migration.run() }
    #expect(await config.load() == original)
  }

  @Test func aConcurrentWriterKeepsItsChange() async throws {
    let config = InMemoryConfigStore(Config(token: "tok", extras: extras))
    let secrets = RacingSecretStore(config: config) {
      $0.dismiss[3] = 20
      $0.extras["racer"] = .int(1)
    }
    let outcome = try await ConfigTokenMigration(config: config, secrets: secrets).run()
    #expect(outcome == .migrated)
    let result = await config.load()
    #expect(result.token == nil)
    #expect(result.dismiss == [3: 20])
    #expect(result.extras == extras.merging(["racer": .int(1)]) { $1 })
  }

  @Test func aTokenChangedByAConcurrentWriterIsNotScrubbed() async throws {
    let config = InMemoryConfigStore(Config(token: "old"))
    let secrets = RacingSecretStore(config: config) { $0.token = "newer" }
    _ = try await ConfigTokenMigration(config: config, secrets: secrets).run()
    #expect(await config.load().token == "newer")
  }

  @Test func aFailingConfigUpdateAfterTheSecretWriteSurfacesAndKeepsBothCopies() async throws {
    let base = InMemoryConfigStore(Config(token: "tok"))
    let secrets = InMemorySecretStore()
    let migration = ConfigTokenMigration(
      config: UpdateFailingConfigStore(base: base), secrets: secrets)
    await #expect(throws: NtfyError.storage("disk full")) { try await migration.run() }
    #expect(await secrets.token() == "tok")
    #expect(await base.load().token == "tok")
    // A retry with a working store finishes the job.
    let retry = try await ConfigTokenMigration(config: base, secrets: secrets).run()
    #expect(retry == .alreadyMigrated)
    #expect(await base.load().token == nil)
  }
}
