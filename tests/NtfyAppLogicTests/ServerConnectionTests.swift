import Foundation
import NtfyCore
import NtfyTesting
import Testing

@testable import NtfyAppLogic

/// A config store whose `update` fails on demand.
private actor FlakyConfigStore: ConfigStore {
  private let base: InMemoryConfigStore
  private var updatesBeforeFailure: Int?

  init(_ config: Config, updatesBeforeFailure: Int?) {
    base = InMemoryConfigStore(config)
    self.updatesBeforeFailure = updatesBeforeFailure
  }

  func load() async -> Config { await base.load() }
  func save(_ config: Config) async { await base.save(config) }
  func update(_ change: @Sendable (inout Config) -> Void) async throws(NtfyError) {
    if let left = updatesBeforeFailure {
      if left == 0 { throw .storage("disk full") }
      updatesBeforeFailure = left - 1
    }
    await base.update(change)
  }
}

/// A config store that cannot be read, and counts the writes it accepts.
private actor UnreadableConfigStore: ConfigStore {
  private(set) var updates = 0

  func load() async throws(NtfyError) -> Config { throw .storage("unreadable") }
  func save(_ config: Config) async {}
  func update(_ change: @Sendable (inout Config) -> Void) async throws(NtfyError) { updates += 1 }
}

private struct FailingSecretStore: SecretStore {
  func token() async -> String? { "tk_old" }
  func setToken(_ token: String) async throws(NtfyError) { throw .permissionDenied }
  func deleteToken() async {}
}

@Suite struct ServerConnectionTests {
  private let old = Config(url: "https://old.example.com")

  private func connection(
    config: any ConfigStore, secrets: any SecretStore = InMemorySecretStore(token: "tk_old")
  ) -> ServerConnection {
    ServerConnection(
      config: config, secrets: secrets, tester: ScriptedServerTester(.ok(topics: [])))
  }

  @Test func aFailingConfigWriteLeavesTheOldTokenAndURL() async {
    let config = FlakyConfigStore(old, updatesBeforeFailure: 0)
    let secrets = InMemorySecretStore(token: "tk_old")
    let result = await connection(config: config, secrets: secrets)
      .testAndSave(urlText: "https://new.example.com", tokenText: "tk_new")
    guard case .invalid(let reason) = result else {
      Issue.record("expected invalid, got \(result)")
      return
    }
    #expect(reason.contains("saving failed"))
    #expect(await config.load().url == "https://old.example.com")
    #expect(await secrets.token() == "tk_old")
  }

  @Test func aFailingKeychainWriteRestoresTheOldURL() async {
    let config = FlakyConfigStore(old, updatesBeforeFailure: nil)
    let result = await connection(config: config, secrets: FailingSecretStore())
      .testAndSave(urlText: "https://new.example.com", tokenText: "tk_new")
    guard case .invalid = result else {
      Issue.record("expected invalid, got \(result)")
      return
    }
    #expect(await config.load().url == "https://old.example.com")
  }

  @Test func anUnreadablePreviousConfigIsNotOverwrittenByTheRollback() async {
    let config = UnreadableConfigStore()
    let result = await connection(config: config, secrets: FailingSecretStore())
      .testAndSave(urlText: "https://new.example.com", tokenText: "tk_new")
    guard case .invalid = result else {
      Issue.record("expected invalid, got \(result)")
      return
    }
    #expect(await config.updates == 1, "only the save, no rollback over a config we could not read")
  }

  @Test func aFailingRollbackIsReported() async {
    let config = FlakyConfigStore(old, updatesBeforeFailure: 1)
    let result = await connection(config: config, secrets: FailingSecretStore())
      .testAndSave(urlText: "https://new.example.com", tokenText: "tk_new")
    guard case .invalid(let reason) = result else {
      Issue.record("expected invalid, got \(result)")
      return
    }
    #expect(reason.contains("previous settings could not be restored"))
  }

  @Test func aFailedServerTestSavesNothing() async {
    let config = InMemoryConfigStore(old)
    let secrets = InMemorySecretStore(token: "tk_old")
    let failing = ServerConnection(
      config: config, secrets: secrets, tester: ScriptedServerTester(.unauthorized))
    let result = await failing.testAndSave(urlText: "https://new.example.com", tokenText: "tk_new")
    #expect(result == .unauthorized)
    #expect(await config.load().url == "https://old.example.com")
    #expect(await secrets.token() == "tk_old")
  }

  @Test func anEmptyTokenFieldReusesTheStoredToken() async {
    let config = InMemoryConfigStore(old)
    let secrets = InMemorySecretStore(token: "tk_old")
    let tester = ScriptedServerTester(.ok(topics: []))
    let result = await ServerConnection(config: config, secrets: secrets, tester: tester)
      .testAndSave(urlText: "https://new.example.com", tokenText: "  ")
    #expect(result == .ok(topics: []))
    #expect(await tester.calls.map(\.token) == ["tk_old"])
    #expect(await secrets.token() == "tk_old")
    #expect(await config.load().url == "https://new.example.com")
  }
}
