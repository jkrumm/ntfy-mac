import Foundation
import NtfyCore

/// What the user can pick in the pause menu.
public enum PauseChoice: Sendable, Hashable {
  case duration(TimeInterval)
  /// The next 08:00 on the calendar's clock (tomorrow's, when it is already past 08:00).
  case untilMorning
  case indefinitely

  /// When the pause ends, as `Config.pausedUntil` stores it.
  public func end(from now: Date, calendar: Calendar) -> Date {
    switch self {
    case .duration(let seconds):
      return now.addingTimeInterval(seconds)
    case .untilMorning:
      let morning = DateComponents(hour: 8, minute: 0)
      return calendar.nextDate(after: now, matching: morning, matchingPolicy: .nextTime)
        ?? now.addingTimeInterval(24 * 60 * 60)
    case .indefinitely:
      return PauseWindow.indefinite
    }
  }
}
