import Foundation

/// A local wall-clock time of day, written `HH:mm` in the config.
public struct ClockTime: Sendable, Hashable, Comparable, CustomStringConvertible {
  public let hour: Int
  public let minute: Int

  /// Fails for an hour outside 0...23 or a minute outside 0...59.
  public init?(hour: Int, minute: Int) {
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    self.hour = hour
    self.minute = minute
  }

  fileprivate init(valid hour: Int, _ minute: Int) {
    self.hour = hour
    self.minute = minute
  }

  /// Parses exactly `HH:mm` (two digits each); anything else is nil.
  public init?(_ text: String) {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCII) }),
      let hour = Int(parts[0]), let minute = Int(parts[1])
    else { return nil }
    self.init(hour: hour, minute: minute)
  }

  public var minuteOfDay: Int { hour * 60 + minute }

  public var description: String { String(format: "%02d:%02d", hour, minute) }

  public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
    lhs.minuteOfDay < rhs.minuteOfDay
  }
}

/// A daily window in local time during which notifications are held back.
public struct QuietHours: Sendable, Hashable {
  public static let defaultStart = ClockTime(valid: 22, 0)
  public static let defaultEnd = ClockTime(valid: 7, 0)

  public var enabled: Bool
  public var start: ClockTime
  /// Exclusive. The window may cross midnight; `start == end` is an empty window (never).
  public var end: ClockTime
  /// Messages at priority 5 ignore the window.
  public var urgentBypass: Bool
  /// What was held shows as one summary notification when the window ends, instead of going out
  /// one by one.
  public var digest: Bool

  public init(
    enabled: Bool = false, start: ClockTime = defaultStart, end: ClockTime = defaultEnd,
    urgentBypass: Bool = true, digest: Bool = true
  ) {
    self.enabled = enabled
    self.start = start
    self.end = end
    self.urgentBypass = urgentBypass
    self.digest = digest
  }

  /// Whether `date` lies inside the window. A disabled schedule contains nothing. Judged by the
  /// calendar's wall clock (hour and minute), so DST days follow the clock on the wall.
  public func contains(_ date: Date, calendar: Calendar) -> Bool {
    guard enabled, start != end else { return false }
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    guard let hour = parts.hour, let minute = parts.minute else { return false }
    let now = hour * 60 + minute
    if start < end { return now >= start.minuteOfDay && now < end.minuteOfDay }
    return now >= start.minuteOfDay || now < end.minuteOfDay
  }

  /// The next moment the wall clock reads `end`, strictly after `date`. A time the clock skips
  /// (spring-forward) resolves to the first instant after the gap. Called from inside the
  /// window this is when it closes.
  public func nextEnd(after date: Date, calendar: Calendar) -> Date {
    let target = DateComponents(hour: end.hour, minute: end.minute, second: 0)
    return calendar.nextDate(after: date, matching: target, matchingPolicy: .nextTime)
      ?? date.addingTimeInterval(24 * 60 * 60)
  }

  private enum Key {
    static let enabled = "enabled"
    static let start = "start"
    static let end = "end"
    static let urgentBypass = "urgentBypass"
    static let digest = "digest"
  }

  /// Reads the `quietHours` object; wrong-typed or malformed fields read as their default.
  init(value: ConfigValue?) {
    let object = value?.objectValue ?? [:]
    func flag(_ key: String, _ fallback: Bool) -> Bool {
      if case .bool(let flag)? = object[key] { return flag }
      return fallback
    }
    self.init(
      enabled: flag(Key.enabled, false),
      start: object[Key.start]?.stringValue.flatMap(ClockTime.init) ?? Self.defaultStart,
      end: object[Key.end]?.stringValue.flatMap(ClockTime.init) ?? Self.defaultEnd,
      urgentBypass: flag(Key.urgentBypass, true),
      digest: flag(Key.digest, true))
  }

  /// The JSON to write, or nil when every field is at its default.
  var configValue: ConfigValue? {
    var object: [String: ConfigValue] = [:]
    if enabled { object[Key.enabled] = .bool(true) }
    if start != Self.defaultStart { object[Key.start] = .string(start.description) }
    if end != Self.defaultEnd { object[Key.end] = .string(end.description) }
    if !urgentBypass { object[Key.urgentBypass] = .bool(false) }
    if !digest { object[Key.digest] = .bool(false) }
    return object.isEmpty ? nil : .object(object)
  }
}
