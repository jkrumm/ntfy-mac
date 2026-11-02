import Foundation

/// Turns readings into a steady meeting state: a signal must hold for `dwell` before the
/// meeting starts, and the meeting ends only `release` after the signal was last seen, because
/// muting drops the microphone bit in the middle of a call.
///
/// A value with no clock of its own: the caller passes the time of each reading, so tests drive
/// it with `FakeClock`. An unreadable reading changes nothing.
public struct MeetingPolicy: Sendable {
  public static let defaultDwell: TimeInterval = 3
  public static let defaultRelease: TimeInterval = 45

  private enum Phase: Sendable {
    case idle
    case pending(since: Date, reason: MeetingReason)
    case active(reason: MeetingReason, lastSeen: Date)
  }

  public let dwell: TimeInterval
  public let release: TimeInterval
  private var phase = Phase.idle

  public init(
    dwell: TimeInterval = MeetingPolicy.defaultDwell,
    release: TimeInterval = MeetingPolicy.defaultRelease
  ) {
    self.dwell = dwell
    self.release = release
  }

  public var state: MeetingState {
    guard case .active(let reason, _) = phase else { return .inactive }
    return .active(reason)
  }

  /// The moment the state may change without a new signal: the end of the dwell, or of the
  /// release latch. Nil when nothing is pending.
  public var nextDeadline: Date? {
    switch phase {
    case .idle: nil
    case .pending(let since, _): since.addingTimeInterval(dwell)
    case .active(_, let lastSeen): lastSeen.addingTimeInterval(release)
    }
  }

  /// Folds in a reading taken at `now` and returns the state after it.
  @discardableResult
  public mutating func evaluate(_ snapshot: MeetingSnapshot, at now: Date) -> MeetingState {
    switch MeetingClassifier.verdict(for: snapshot) {
    case .meeting(let reason): signal(reason, at: now)
    case .none: silence(at: now)
    case .unknown: break
    }
    return state
  }

  private mutating func signal(_ reason: MeetingReason, at now: Date) {
    switch phase {
    case .idle:
      phase =
        dwell <= 0 ? .active(reason: reason, lastSeen: now) : .pending(since: now, reason: reason)
    case .pending(let since, _):
      phase =
        now.timeIntervalSince(since) >= dwell
        ? .active(reason: reason, lastSeen: now) : .pending(since: since, reason: reason)
    case .active:
      phase = .active(reason: reason, lastSeen: now)
    }
  }

  private mutating func silence(at now: Date) {
    switch phase {
    case .idle: break
    case .pending: phase = .idle
    case .active(_, let lastSeen):
      if now.timeIntervalSince(lastSeen) >= release { phase = .idle }
    }
  }
}
