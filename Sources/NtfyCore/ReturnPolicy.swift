import Foundation

/// Decides when the user is back and a digest of what they missed is due. Pure: it is told what
/// happened and when, and answers with the moment to summarize from.
///
/// - Leaving is a lock, a display sleep or a system sleep; the first one starts the absence.
/// - Returning is the displays coming back or an unlock (`didWake` alone can be a dark wake). A
///   digest is due when the absence lasted at least `minAwayMinutes`.
/// - Opening the History window or the menu bar is a check: a digest is due when the last check is
///   at least `minAwayMinutes` old, and the open counts as a check either way.
/// - The last check also moves when a digest was posted (`markChecked`), so the next digest
///   starts where the last one stopped. Nothing is persisted: it starts at launch.
public struct ReturnPolicy: Sendable {
  private var awaySince: Date?
  private var lastCheck: Date

  public init(now: Date) {
    lastCheck = now
  }

  /// The start of the window to summarize when this event ends a long enough absence, else nil.
  public mutating func handle(
    _ event: SystemEvent, now: Date, settings: SummarySettings
  ) -> Date? {
    switch event {
    case .willSleep, .screensDidSleep, .screenLocked:
      awaySince = awaySince ?? now
      return nil
    case .screensDidWake, .screenUnlocked:
      guard let left = awaySince else { return nil }
      awaySince = nil
      guard settings.isConfigured, now.timeIntervalSince(left) >= minimum(settings) else {
        return nil
      }
      return lastCheck
    case .didWake, .pathChanged:
      return nil
    }
  }

  /// The History window or the menu bar was opened.
  public mutating func windowOpened(now: Date, settings: SummarySettings) -> Date? {
    let previous = lastCheck
    lastCheck = now
    guard settings.isConfigured, now.timeIntervalSince(previous) >= minimum(settings) else {
      return nil
    }
    return previous
  }

  /// A digest was posted.
  public mutating func markChecked(at now: Date) {
    lastCheck = now
  }

  private func minimum(_ settings: SummarySettings) -> TimeInterval {
    TimeInterval(settings.minAwayMinutes * 60)
  }
}

/// Builds the summarizer for a config, or nothing when the digest is off, has no endpoint or no
/// key. Nothing else ever constructs one, so a disabled digest makes no network request.
public struct SummarizerProvider: Sendable {
  public typealias Make =
    @Sendable (
      _ endpoint: String, _ key: String, _ model: String, _ allowInsecure: Bool
    ) -> (any MessageSummarizing)?

  private let keys: any SecretStore
  private let make: Make

  public init(keys: any SecretStore, make: @escaping Make) {
    self.keys = keys
    self.make = make
  }

  public func summarizer(for config: Config) async -> (any MessageSummarizing)? {
    guard config.summary.isConfigured, let endpoint = config.summary.endpoint,
      let key = try? await keys.token(), !key.isEmpty
    else { return nil }
    return make(endpoint, key, config.summary.model, config.allowInsecure)
  }

  /// For the Settings test: asks `make` with the typed values, whatever is saved.
  public func summarizer(
    endpoint: String, model: String, allowInsecure: Bool
  ) async -> (any MessageSummarizing)? {
    guard let key = try? await keys.token(), !key.isEmpty else { return nil }
    return make(endpoint, key, model, allowInsecure)
  }
}

/// Whether the user's own hold on notifications covers the digest: a manual pause, quiet hours or
/// a meeting. The digest is a notification, so it keeps to them; it waits for the next return and
/// the window it would have covered rolls over. Priority 5 gets no bypass: a digest has no single
/// priority.
public enum DigestHold {
  public static func holds(
    _ config: Config, meeting: MeetingState, meetingKnown: Bool, now: Date, calendar: Calendar
  ) -> Bool {
    if let until = config.pausedUntil, until > now { return true }
    if config.quietHours.contains(now, calendar: calendar) { return true }
    if config.meeting.effectiveState(detected: meeting, at: now).isActive { return true }
    return config.meeting.mode == .pause && !meetingKnown
  }
}
