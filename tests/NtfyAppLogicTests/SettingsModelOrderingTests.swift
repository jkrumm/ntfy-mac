import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

/// A config store whose first `load` returns what the file held when it was called, but only
/// once released: a slow read that finishes after later writes.
private actor GatedConfigStore: ConfigStore {
  private let base = InMemoryConfigStore()
  private var gate: CheckedContinuation<Void, Never>?
  private var armed = true
  private(set) var isBlocked = false

  func load() async -> Config {
    let snapshot = await base.load()
    guard armed else { return snapshot }
    armed = false
    isBlocked = true
    await withCheckedContinuation { gate = $0 }
    return snapshot
  }

  func release() {
    gate?.resume()
    gate = nil
    isBlocked = false
  }

  func save(_ config: Config) async { await base.save(config) }
  func update(_ change: @Sendable (inout Config) -> Void) async { await base.update(change) }
}

/// A config store whose writes each wait to be released, one at a time, in arrival order.
private actor StepwiseConfigStore: ConfigStore {
  private let base = InMemoryConfigStore()
  private var waiting: [CheckedContinuation<Void, Never>] = []

  var waitingCount: Int { waiting.count }

  func releaseNext() {
    guard !waiting.isEmpty else { return }
    waiting.removeFirst().resume()
  }

  func load() async -> Config { await base.load() }
  func save(_ config: Config) async { await base.save(config) }
  func update(_ change: @Sendable (inout Config) -> Void) async {
    await withCheckedContinuation { waiting.append($0) }
    await base.update(change)
  }
}

@MainActor @Suite struct SettingsModelOrderingTests {
  @Test func aSlowLoadFinishingAfterAWriteDoesNotRevertIt() async {
    let store = GatedConfigStore()
    let rig = SettingsRig(store: store)
    let slowLoad = Task { await rig.model.reload() }
    while !(await store.isBlocked) { await Task.yield() }
    let write = Task { await rig.model.setAllowInsecure(true) }
    #expect(await rig.eventually { rig.model.config.allowInsecure })
    await store.release()
    await slowLoad.value
    #expect(rig.model.config.allowInsecure, "the stale read must not snap the control back")
    await write.value
    #expect(rig.model.config.allowInsecure)
    #expect(await store.load().allowInsecure)
  }

  @Test func writesRunOneAfterTheOtherAndBothStick() async {
    let rig = SettingsRig()
    async let first: Void = rig.model.setAllowInsecure(true)
    async let second: Void = rig.model.setAllowPrivateNetworkActions(true)
    _ = await (first, second)
    #expect(rig.model.config.allowInsecure && rig.model.config.allowPrivateNetworkActions)
    let stored = await rig.current
    #expect(stored.allowInsecure && stored.allowPrivateNetworkActions)
  }

  @Test func queuedWritesReloadDoesNotRevertALaterEditBeforeItsOwnWriteRuns() async {
    let store = StepwiseConfigStore()
    let rig = SettingsRig(store: store)
    let first = Task { await rig.model.setAllowInsecure(true) }
    while await store.waitingCount < 1 { await Task.yield() }
    let second = Task { await rig.model.setAllowPrivateNetworkActions(true) }
    #expect(await rig.eventually { rig.model.config.allowPrivateNetworkActions })
    // The first write finishes and reloads; the second one has not reached the file yet.
    await store.releaseNext()
    while await store.waitingCount < 1 { await Task.yield() }
    #expect(rig.model.config.allowInsecure)
    #expect(rig.model.config.allowPrivateNetworkActions, "the first reload must not revert it")
    await store.releaseNext()
    await first.value
    await second.value
    #expect(rig.model.config.allowInsecure && rig.model.config.allowPrivateNetworkActions)
  }
}
