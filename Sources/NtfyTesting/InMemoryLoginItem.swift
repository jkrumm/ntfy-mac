import NtfyCore
import Synchronization

/// A login item that only remembers what it was told.
public final class InMemoryLoginItem: LoginItemControlling {
  private let current: Mutex<LoginItemState>
  private let approvalNeeded: Bool

  /// - Parameter requiresApproval: Registering ends in `requiresApproval` instead of `enabled`.
  public init(_ state: LoginItemState = .notRegistered, requiresApproval: Bool = false) {
    current = Mutex(state)
    approvalNeeded = requiresApproval
  }

  public func state() -> LoginItemState { current.withLock { $0 } }

  public func setEnabled(_ enabled: Bool) -> LoginItemState {
    current.withLock { state in
      state = enabled ? (approvalNeeded ? .requiresApproval : .enabled) : .notRegistered
      return state
    }
  }
}
