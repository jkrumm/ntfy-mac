import NtfyCore
import Observation

/// What the menu bar's "Check for Updates…" row shows. The updater drives `state`; the row calls
/// `check`.
@MainActor @Observable
public final class UpdateMenuModel {
  public enum State: Equatable, Sendable {
    /// No row: a development build has nothing to offer.
    case hidden
    /// A disabled row with the reason.
    case blocked(String)
    case ready
    /// A scheduled check found this version and left the decision to the user.
    case available(String)
  }

  public private(set) var state: State
  /// What the row does; the updater sets it.
  @ObservationIgnored public var onCheck: @MainActor () -> Void

  public init(state: State = .hidden, onCheck: @escaping @MainActor () -> Void = {}) {
    self.state = state
    self.onCheck = onCheck
  }

  /// The row for an updater that cannot run.
  public static func state(for reason: UpdateUnavailableReason) -> State {
    switch reason {
    case .unsigned: .hidden
    case .homebrew: .blocked("Old Homebrew formula copy: run brew update to move to the cask")
    case .disabled: .blocked("Updates are turned off (NTFY_MAC_NO_SELF_UPDATE)")
    case .teamMismatch: .blocked("Updates are off: this build is signed by another team")
    }
  }

  public func set(_ state: State) { self.state = state }

  public func check() { onCheck() }
}
