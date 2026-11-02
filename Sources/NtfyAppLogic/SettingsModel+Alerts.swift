import Foundation
import NtfyCore

extension SettingsModel {
  // MARK: Re-alert

  public func setReAlert(_ enabled: Bool) async {
    await write { $0.reAlert = enabled }
  }

  /// Seconds between repeats; below 1 is refused, as the CLI does.
  public func setReAlertInterval(seconds: Int) async {
    guard seconds > 0 else {
      refuse("The interval must be a whole number of seconds above 0.")
      return
    }
    await write { $0.reAlertIntervalSeconds = seconds }
  }

  /// A priority from 1 to 5; other values are pinned to the range.
  public func setReAlertMinPriority(_ priority: Int) async {
    let pinned = Priority(clamping: priority).rawValue
    await write { $0.reAlertMinPriority = pinned }
  }

  /// How often a message is repeated; below 0 is refused.
  public func setReAlertMaxRepeats(_ repeats: Int) async {
    guard repeats >= 0 else {
      refuse("The maximum must be 0 or more.")
      return
    }
    await write { $0.reAlertMaxRepeats = repeats }
  }

  // MARK: Quiet hours

  public func setQuietHoursEnabled(_ enabled: Bool) async {
    guard !enabled || config.quietHours.start != config.quietHours.end else {
      refuse("Quiet hours need different start and end times.")
      return
    }
    await write { $0.quietHours.enabled = enabled }
  }

  public func setQuietHoursStart(_ time: ClockTime) async {
    guard time != config.quietHours.end else {
      refuse("The window must have different start and end times.")
      return
    }
    await write { $0.quietHours.start = time }
  }

  public func setQuietHoursEnd(_ time: ClockTime) async {
    guard time != config.quietHours.start else {
      refuse("The window must have different start and end times.")
      return
    }
    await write { $0.quietHours.end = time }
  }

  public func setUrgentBypass(_ bypass: Bool) async {
    await write { $0.quietHours.urgentBypass = bypass }
  }

  public func setDigest(_ digest: Bool) async {
    await write { $0.quietHours.digest = digest }
  }

  /// A date picker's value for a time of day (today, in the model's calendar).
  public func date(for time: ClockTime) -> Date {
    calendar.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
  }

  /// The wall-clock time of day a date picker returned.
  public func clockTime(from date: Date) -> ClockTime {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0) ?? QuietHours.defaultStart
  }
}
