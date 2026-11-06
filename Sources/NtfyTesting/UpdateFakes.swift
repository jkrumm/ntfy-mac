import NtfyCore
import Synchronization

/// An updater that answers from a script and records what it was asked.
public final class ScriptedUpdater: UpdateControlling {
  public enum Call: Sendable, Hashable { case status, probe, interactive }

  private struct State {
    var calls: [Call] = []
  }

  private let state = Mutex(State())
  private let known: UpdateStatus
  private let probeOutcome: Result<UpdateStatus, NtfyError>

  /// - Parameters:
  ///   - status: What `status` and `startInteractive` report.
  ///   - probe: What `probe` ends with; defaults to `status`.
  public init(status: UpdateStatus, probe: Result<UpdateStatus, NtfyError>? = nil) {
    known = status
    probeOutcome = probe ?? .success(status)
  }

  public var calls: [Call] { state.withLock { $0.calls } }

  public func status() async -> UpdateStatus {
    state.withLock { $0.calls.append(.status) }
    return known
  }

  public func probe() async throws(NtfyError) -> UpdateStatus {
    state.withLock { $0.calls.append(.probe) }
    return try probeOutcome.get()
  }

  public func startInteractive() async -> UpdateStatus {
    state.withLock { $0.calls.append(.interactive) }
    return known
  }
}

public struct FixedSigning: SigningInspecting {
  private let info: SigningInfo

  public init(_ info: SigningInfo) { self.info = info }

  public func inspect() -> SigningInfo { info }
}

public struct FixedEntitlements: EntitlementProbing {
  private let granted: Set<Entitlement>

  public init(_ granted: Set<Entitlement> = []) { self.granted = granted }

  public func holds(_ entitlement: Entitlement) -> Bool { granted.contains(entitlement) }
}

public final class InMemoryTeamPinStore: TeamPinStoring {
  private let team: Mutex<String?>

  public init(_ team: String? = nil) { self.team = Mutex(team) }

  public func recorded() -> String? { team.withLock { $0 } }

  public func record(_ teamID: String) { team.withLock { $0 = teamID } }
}
