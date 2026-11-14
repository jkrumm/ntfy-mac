import Foundation
import NtfyCore
import NtfyPlatform
import NtfyTesting
import Synchronization
import Testing

@testable import NtfyAppLogic

private final class Activator: RunningInstanceActivating {
  private let visible: Bool
  private let calls = Mutex(0)
  init(visible: Bool) { self.visible = visible }
  var activations: Int { calls.withLock { $0 } }
  func activateOther() -> Bool {
    calls.withLock { $0 += 1 }
    return visible
  }
}

private final class Pauses: Sendable {
  private let count = Mutex(0)
  private let onPause: @Sendable (Int) -> Void
  init(_ onPause: @escaping @Sendable (Int) -> Void = { _ in }) { self.onPause = onPause }
  var total: Int { count.withLock { $0 } }
  func pause() {
    let now = count.withLock { value -> Int in
      value += 1
      return value
    }
    onPause(now)
  }
}

@Suite struct SingleInstanceGateTests {
  private func gate(
    _ lock: any InstanceLocking, _ activator: Activator, _ pauses: Pauses = Pauses()
  ) -> SingleInstanceGate {
    SingleInstanceGate(lock: lock, activator: activator, pause: { _ in pauses.pause() })
  }

  private func lease(_ admission: InstanceAdmission) -> (any InstanceLease)? {
    guard case .run(let lease) = admission else { return nil }
    return lease
  }

  @Test func theFirstCopyRunsAndHoldsTheLock() {
    let lock = InMemoryInstanceLock()
    let activator = Activator(visible: false)
    let admission = gate(lock, activator).admit()
    #expect(lease(admission) != nil)
    #expect(lock.isHeld)
    #expect(activator.activations == 0)
  }

  @Test func aSecondCopyYieldsWhileTheFirstHoldsTheLockAndActivatesIt() {
    let lock = InMemoryInstanceLock()
    let first = gate(lock, Activator(visible: true)).admit()
    let activator = Activator(visible: true)
    let pauses = Pauses()
    let second = gate(lock, activator, pauses).admit()
    guard case .yield = second else {
      Issue.record("a second instance was admitted")
      return
    }
    #expect(activator.activations == 1)
    #expect(pauses.total == 40)
    #expect(lease(first) != nil && lock.isHeld)
  }

  @Test func aCopyStartedAfterTheFirstQuitRuns() {
    let lock = InMemoryInstanceLock()
    let first = gate(lock, Activator(visible: true)).admit()
    lease(first)?.release()
    #expect(!lock.isHeld)
    #expect(lease(gate(lock, Activator(visible: true)).admit()) != nil)
  }

  @Test func aQuittingInstanceIsWaitedForNotReplacedByNothing() {
    let lock = InMemoryInstanceLock()
    let first = lease(gate(lock, Activator(visible: true)).admit())
    // The old copy is still shutting down, and still visible as a running app, until the lock frees.
    let pauses = Pauses { if $0 == 3 { first?.release() } }
    let activator = Activator(visible: true)
    let second = gate(lock, activator, pauses).admit()
    #expect(lease(second) != nil)
    #expect(pauses.total == 3)
    #expect(activator.activations == 1)
  }

  @Test func aLockHeldByNobodyVisibleIsGivenUpAfterABoundedWait() {
    let lock = InMemoryInstanceLock()
    let first = gate(lock, Activator(visible: true)).admit()
    let pauses = Pauses()
    let second = gate(lock, Activator(visible: false), pauses).admit()
    guard case .yield = second else {
      Issue.record("a second instance was admitted")
      return
    }
    #expect(pauses.total == 40)
    #expect(lease(first) != nil)
  }

  @Test func aBrokenLockNeverKeepsTheAppFromStarting() {
    let lock = InMemoryInstanceLock(failure: .storage("disk full"))
    let activator = Activator(visible: true)
    guard case .run(let held) = gate(lock, activator).admit() else {
      Issue.record("the app did not start")
      return
    }
    #expect(held == nil)
    #expect(activator.activations == 0)
  }

  @Test func theRealFileLockGivesTheSameAnswers() throws {
    let dir = FileManager.default.temporaryDirectory.appending(
      path: "ntfy-mac-gate-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    let lock = FileInstanceLock(url: dir.appending(path: "app.instance.lock"))
    let first = lease(gate(lock, Activator(visible: true)).admit())
    #expect(first != nil)
    guard case .yield = gate(lock, Activator(visible: true)).admit() else {
      Issue.record("a second instance was admitted")
      return
    }
    first?.release()
    #expect(lease(gate(lock, Activator(visible: true)).admit()) != nil)
  }
}
