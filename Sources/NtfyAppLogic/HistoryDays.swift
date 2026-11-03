import Foundation

/// How a day header reads.
public enum DayLabel: Sendable, Hashable {
  case today
  case yesterday
  /// Any other day; `includesYear` when it is not in the current year.
  case date(Date, includesYear: Bool)

  public init(day: Date, now: Date, calendar: Calendar) {
    if calendar.isDate(day, inSameDayAs: now) {
      self = .today
    } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(day, inSameDayAs: yesterday)
    {
      self = .yesterday
    } else {
      self = .date(day, includesYear: !calendar.isDate(day, equalTo: now, toGranularity: .year))
    }
  }
}

/// The messages of one calendar day, newest first.
public struct DayGroup: Sendable, Hashable, Identifiable {
  /// Midnight of the day on the calendar that grouped it.
  public let day: Date
  public let rows: [MessageRow]

  public var id: TimeInterval { day.timeIntervalSince1970 }

  public init(day: Date, rows: [MessageRow]) {
    self.day = day
    self.rows = rows
  }

  public func label(now: Date, calendar: Calendar) -> DayLabel {
    DayLabel(day: day, now: now, calendar: calendar)
  }
}

public enum HistoryGrouping {
  /// Newest first; messages at the same instant by id.
  private static func newestFirst(_ rows: [MessageRow]) -> [MessageRow] {
    rows.sorted { ($0.time, $0.id) > ($1.time, $1.id) }
  }

  /// The log: days newest first, messages newest first within a day. Messages at the same
  /// instant keep a fixed order (by id), so rows never swap places on a refresh.
  public static func days(of rows: [MessageRow], calendar: Calendar) -> [DayGroup] {
    var groups: [DayGroup] = []
    var day: Date?
    var current: [MessageRow] = []
    for row in newestFirst(rows) {
      let start = calendar.startOfDay(for: row.time)
      if start != day {
        if let day { groups.append(DayGroup(day: day, rows: current)) }
        day = start
        current = []
      }
      current.append(row)
    }
    if let day { groups.append(DayGroup(day: day, rows: current)) }
    return groups
  }
}
