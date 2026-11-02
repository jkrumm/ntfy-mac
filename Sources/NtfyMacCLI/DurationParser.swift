import Foundation

/// Durations as people type them: `90s`, `30m`, `2h`, `1d`, or a mix such as `1h30m`.
enum DurationParser {
  /// Seconds, or nil for anything that is not one or more `<digits><s|m|h|d>` groups or is zero.
  static func seconds(_ text: String) -> TimeInterval? {
    var total: TimeInterval = 0
    var digits = ""
    var groups = 0
    for character in text.lowercased() {
      if character.isASCII, character.isNumber {
        digits.append(character)
        continue
      }
      guard let value = TimeInterval(digits), let unit = unit(character) else { return nil }
      total += value * unit
      digits = ""
      groups += 1
    }
    guard digits.isEmpty, groups > 0, total > 0, total.isFinite else { return nil }
    return total
  }

  private static func unit(_ character: Character) -> TimeInterval? {
    switch character {
    case "s": 1
    case "m": 60
    case "h": 3600
    case "d": 86_400
    default: nil
    }
  }
}

/// A point in time given either as a duration ago (`2h`) or as an ISO 8601 timestamp.
enum TimePoint {
  static func parse(_ text: String, now: Date) -> Date? {
    if let seconds = DurationParser.seconds(text) { return now.addingTimeInterval(-seconds) }
    return iso8601(text)
  }

  static func iso8601(_ text: String) -> Date? {
    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
      ?? (try? Date.ISO8601FormatStyle().parse(text))
  }
}
