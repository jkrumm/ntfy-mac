/// ntfy message priority, always within `1...5`.
public struct Priority: Sendable, Hashable, Comparable, Codable {
  public static let range = 1...5

  public static let min = Priority(clamping: 1)
  public static let low = Priority(clamping: 2)
  public static let `default` = Priority(clamping: 3)
  public static let high = Priority(clamping: 4)
  public static let max = Priority(clamping: 5)

  public let rawValue: Int

  /// Fails for values outside `1...5`.
  public init?(rawValue: Int) {
    guard Self.range.contains(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  /// Pins out-of-range values to the nearest bound.
  public init(clamping value: Int) {
    rawValue = Swift.min(Swift.max(value, Self.range.lowerBound), Self.range.upperBound)
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(Int.self)
    guard let priority = Priority(rawValue: value) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "priority \(value) not in 1...5"))
    }
    self = priority
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// The name the CLI and the settings window use: min, low, default, high, urgent.
  public var label: String {
    switch rawValue {
    case 5: "urgent"
    case 4: "high"
    case 3: "default"
    case 2: "low"
    default: "min"
    }
  }

  public static func < (lhs: Priority, rhs: Priority) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
