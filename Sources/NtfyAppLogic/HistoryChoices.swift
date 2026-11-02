import Foundation

/// How far back the History window looks.
public enum HistoryDateFilter: String, Sendable, CaseIterable, Hashable {
  case all
  case today
  case week
  case month

  public var title: String {
    switch self {
    case .all: "All time"
    case .today: "Today"
    case .week: "Last 7 days"
    case .month: "Last 30 days"
    }
  }

  /// The earliest time to show; nil for everything. "Today" starts at midnight on the calendar's
  /// clock, the others count back from `now`.
  public func start(from now: Date, calendar: Calendar) -> Date? {
    switch self {
    case .all: nil
    case .today: calendar.startOfDay(for: now)
    case .week: now.addingTimeInterval(-7 * 24 * 60 * 60)
    case .month: now.addingTimeInterval(-30 * 24 * 60 * 60)
    }
  }
}

/// When the window offers to show a message again.
public enum RemindChoice: String, Sendable, CaseIterable, Hashable {
  case fifteenMinutes
  case oneHour
  case tomorrowMorning

  public var title: String {
    switch self {
    case .fifteenMinutes: "In 15 minutes"
    case .oneHour: "In 1 hour"
    case .tomorrowMorning: "Tomorrow at 08:00"
    }
  }

  /// "Tomorrow" is the next calendar day, even in the small hours.
  public func time(from now: Date, calendar: Calendar) -> Date {
    switch self {
    case .fifteenMinutes:
      return now.addingTimeInterval(15 * 60)
    case .oneHour:
      return now.addingTimeInterval(60 * 60)
    case .tomorrowMorning:
      let today = calendar.startOfDay(for: now)
      let tomorrow =
        calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
      return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
        ?? tomorrow.addingTimeInterval(8 * 60 * 60)
    }
  }
}

/// Where fetching an attachment for the preview stands.
public enum AttachmentState: Sendable, Hashable {
  case idle
  case loading
  /// The local file to preview or Quick Look.
  case ready(URL)
  /// A message the window can show.
  case failed(String)
}
