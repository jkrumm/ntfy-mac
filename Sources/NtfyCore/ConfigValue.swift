import Foundation

/// A JSON value of any shape. Lets the config and state codecs carry keys they do not know, so
/// a write never drops what another version (or the user) put in the file.
public enum ConfigValue: Sendable, Hashable, Codable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([ConfigValue])
  case object([String: ConfigValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([ConfigValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: ConfigValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// A number as JSON writes it: whole values become integers (`30`, not `30.0`).
  public static func number(_ value: Double) -> ConfigValue {
    if value.rounded() == value, let whole = Int(exactly: value) { return .int(whole) }
    return .double(value)
  }

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var numberValue: Double? {
    switch self {
    case .int(let value): Double(value)
    case .double(let value): value
    default: nil
    }
  }

  /// A whole JSON number as an `Int`; fractions and other types are nil.
  public var intValue: Int? {
    switch self {
    case .int(let value): value
    case .double(let value): Int(exactly: value)
    default: nil
    }
  }

  /// Whether this is `true`; any other value, including other types, is false.
  public var isTrue: Bool {
    guard case .bool(let value) = self else { return false }
    return value
  }

  public var arrayValue: [ConfigValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  public var objectValue: [String: ConfigValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }
}

extension ConfigValue {
  /// The top-level JSON object in `data`, or nil when it is empty, malformed or not an object.
  public static func parseObject(_ data: Data) -> [String: ConfigValue]? {
    try? JSONDecoder().decode([String: ConfigValue].self, from: data)
  }

  /// Pretty-printed with sorted keys and a trailing newline, the shape the 1.x files had.
  public static func encodeObject(_ object: [String: ConfigValue]) throws(NtfyError) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      return try encoder.encode(object) + Data("\n".utf8)
    } catch {
      throw .storage("cannot encode JSON: \(error)")
    }
  }
}
