import Foundation

/// One message in the thread: everything a bubble shows, and whose it is.
public struct ChatMessage: Sendable, Hashable, Identifiable {
  public let detail: MessageDetail
  /// Published by this app, so the bubble sits on the right.
  public let isOwn: Bool

  public var id: String { detail.id }
  public var key: MessageKey { detail.key }
  public var time: Date { detail.time }

  public init(detail: MessageDetail, isOwn: Bool) {
    self.detail = detail
    self.isOwn = isOwn
  }
}

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

/// The messages of one calendar day, oldest first.
public struct DayGroup: Sendable, Hashable, Identifiable {
  /// Midnight of the day on the calendar that grouped it.
  public let day: Date
  public let messages: [ChatMessage]

  public var id: TimeInterval { day.timeIntervalSince1970 }

  public init(day: Date, messages: [ChatMessage]) {
    self.day = day
    self.messages = messages
  }

  public func label(now: Date, calendar: Calendar) -> DayLabel {
    DayLabel(day: day, now: now, calendar: calendar)
  }
}

public enum ChatGrouping {
  /// Oldest first; messages at the same instant by id.
  public static func chronological(_ messages: [ChatMessage]) -> [ChatMessage] {
    messages.sorted { ($0.time, $0.id) < ($1.time, $1.id) }
  }

  /// Chronological thread: days oldest first, messages oldest first within a day. Messages at
  /// the same instant keep a fixed order (by id), so bubbles never swap places on a refresh.
  public static func days(of messages: [ChatMessage], calendar: Calendar) -> [DayGroup] {
    var groups: [DayGroup] = []
    var day: Date?
    var current: [ChatMessage] = []
    for message in chronological(messages) {
      let start = calendar.startOfDay(for: message.time)
      if start != day {
        if let day { groups.append(DayGroup(day: day, messages: current)) }
        day = start
        current = []
      }
      current.append(message)
    }
    if let day { groups.append(DayGroup(day: day, messages: current)) }
    return groups
  }
}
