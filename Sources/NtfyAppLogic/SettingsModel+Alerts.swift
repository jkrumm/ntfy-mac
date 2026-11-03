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

  /// What re-alert does with the current settings, for the section's footer. It names which
  /// priorities re-alert: the same ones that get an Acknowledge button (`AcknowledgePolicy`).
  public var reAlertSummary: String {
    guard config.reAlert else {
      return "Re-alert is off: every message notifies once, whatever its priority."
    }
    let minimum = Priority(clamping: config.reAlertMinPriority)
    let scope =
      minimum == .max
      ? "Only urgent (priority 5) messages"
      : "Messages with priority \(minimum.rawValue) (\(minimum.label)) or higher"
    let every = Self.durationText(seconds: config.reAlertIntervalSeconds)
    let repeats = config.reAlertMaxRepeats == 1 ? "once" : "\(config.reAlertMaxRepeats) times"
    return "\(scope) notify again every \(every), up to \(repeats), until you acknowledge them. "
      + "Lower priorities never re-alert, and only these messages have an Acknowledge button "
      + "in the menu and in History."
  }

  /// `300` is "5 minutes", `90` is "90 seconds".
  static func durationText(seconds: Int) -> String {
    if seconds >= 3600, seconds % 3600 == 0 {
      let hours = seconds / 3600
      return hours == 1 ? "hour" : "\(hours) hours"
    }
    if seconds >= 60, seconds % 60 == 0 {
      let minutes = seconds / 60
      return minutes == 1 ? "minute" : "\(minutes) minutes"
    }
    return seconds == 1 ? "second" : "\(seconds) seconds"
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
