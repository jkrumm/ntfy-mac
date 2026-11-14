import Foundation
import NtfyCore

/// Brings another running copy of this app to the front.
public protocol RunningInstanceActivating: Sendable {
  /// `false` when no other copy is running.
  func activateOther() -> Bool
}

/// What a starting copy of the app does: run, or hand over to the instance that already runs.
public enum InstanceAdmission: Sendable {
  /// Carry on. The lease is `nil` only when the lock itself could not be used: a broken lock must
  /// never keep the app from starting.
  case run(holding: (any InstanceLease)?)
  /// Another instance runs and has been activated; quit now, touching nothing.
  case yield
}

/// Makes the app single-instance per user, whichever bundle (direct copy, cask copy) is started.
/// A copy that does not get the lock activates the running one and yields. A lock that is held
/// while no other copy is visible belongs to an instance that is quitting (an update or an
/// install restarts the app), so the gate waits a bounded time for it before it yields.
public struct SingleInstanceGate: Sendable {
  /// A quitting instance stops within its three second termination budget.
  static let patience = Duration.seconds(4)
  static let interval = Duration.milliseconds(100)

  private let lock: any InstanceLocking
  private let activator: any RunningInstanceActivating
  private let pause: @Sendable (Duration) -> Void
  private let log: @Sendable (String) -> Void

  public init(
    lock: any InstanceLocking, activator: any RunningInstanceActivating,
    pause: @escaping @Sendable (Duration) -> Void = SingleInstanceGate.blockingSleep,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.lock = lock
    self.activator = activator
    self.pause = pause
    self.log = log
  }

  /// Blocks the calling thread; the gate runs before anything else exists to be blocked.
  public static func blockingSleep(_ duration: Duration) {
    let parts = duration.components
    Thread.sleep(forTimeInterval: Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
  }

  public func admit() -> InstanceAdmission {
    var waited = Duration.zero
    while true {
      do {
        if let lease = try lock.acquire() { return .run(holding: lease) }
      } catch {
        log("instance lock unusable, starting anyway: \(error)")
        return .run(holding: nil)
      }
      if activator.activateOther() {
        log("another instance runs; activated it and quitting")
        return .yield
      }
      guard waited < Self.patience else {
        log("the instance lock is held but no other copy is visible; quitting")
        return .yield
      }
      pause(Self.interval)
      waited += Self.interval
    }
  }
}
