import Foundation

/// What the user decided for one topic. A topic without settings behaves like the defaults.
public struct TopicSettings: Sendable, Hashable {
  /// Stored in the history, never notified.
  public var mute: Bool
  /// Messages below this priority (1...5) are stored but not notified; nil means no filter.
  public var minPriority: Int?
  /// Prefixed to the notification title.
  public var emoji: String?

  public init(mute: Bool = false, minPriority: Int? = nil, emoji: String? = nil) {
    self.mute = mute
    self.minPriority = minPriority.map { Priority(clamping: $0).rawValue }
    self.emoji = emoji
  }

  /// Whether a message of this priority is stored without a notification.
  public func suppresses(_ priority: Priority) -> Bool {
    if mute { return true }
    guard let minPriority else { return false }
    return priority.rawValue < minPriority
  }

  private enum Key {
    static let mute = "mute"
    static let minPriority = "minPriority"
    static let emoji = "emoji"
  }

  /// Reads one topic's object; wrong-typed fields read as their default, and nil means the value
  /// is not an object.
  init?(value: ConfigValue) {
    guard let object = value.objectValue else { return nil }
    let emoji = object[Key.emoji]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.init(
      mute: object[Key.mute]?.isTrue ?? false,
      minPriority: object[Key.minPriority]?.intValue,
      emoji: emoji.flatMap { $0.isEmpty ? nil : $0 })
  }

  /// The JSON to write, or nil when every field is at its default.
  var configValue: ConfigValue? {
    var object: [String: ConfigValue] = [:]
    if mute { object[Key.mute] = .bool(true) }
    if let minPriority { object[Key.minPriority] = .int(minPriority) }
    if let emoji, !emoji.isEmpty { object[Key.emoji] = .string(emoji) }
    return object.isEmpty ? nil : .object(object)
  }
}
