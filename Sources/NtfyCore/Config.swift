import Foundation

/// What a per-priority sound setting says. A priority without an entry uses the default sound.
public enum ConfigSound: Sendable, Hashable {
  /// Play no sound (`null` in the file).
  case silent
  case named(String)
}

/// The persisted shape of `~/.config/ntfy-mac/config.json`, exactly as stored: nothing is
/// validated or merged with the environment here (see `ConfigResolver`).
///
/// Keys this version does not know live in `extras` and are written back untouched, as 1.x did
/// when it merged fields into the existing file. A known key whose value has the wrong JSON type
/// is read as absent and is gone after the next write.
public struct Config: Sendable, Hashable {
  public var url: String?
  /// The 1.x plaintext token. The Keychain holds it from 2.0 on; `ConfigTokenMigration` scrubs it.
  public var token: String?
  /// Per-priority (1...5) sound overrides.
  public var sounds: [Int: ConfigSound]
  /// Per-priority (1...5) auto-dismiss seconds; 0 means never.
  public var dismiss: [Int: Double]
  public var extraTopics: [String]
  /// Lets the token travel over plain http to a non-loopback server (a 1.x setup). Off by default.
  public var allowInsecure: Bool
  /// Every other top-level key, preserved verbatim.
  public var extras: [String: ConfigValue]

  public init(
    url: String? = nil,
    token: String? = nil,
    sounds: [Int: ConfigSound] = [:],
    dismiss: [Int: Double] = [:],
    extraTopics: [String] = [],
    allowInsecure: Bool = false,
    extras: [String: ConfigValue] = [:]
  ) {
    self.url = url
    self.token = token
    self.sounds = sounds
    self.dismiss = dismiss
    self.extraTopics = extraTopics
    self.allowInsecure = allowInsecure
    self.extras = extras
  }

  private enum Key {
    static let url = "url"
    static let token = "token"
    static let sounds = "sounds"
    static let dismiss = "dismiss"
    static let extraTopics = "extraTopics"
    static let allowInsecure = "allowInsecure"
    static let known: Set<String> = [url, token, sounds, dismiss, extraTopics, allowInsecure]
  }

  private static let priorities = 1...5

  /// Builds a config from a decoded JSON object.
  public init(object: [String: ConfigValue]) {
    url = object[Key.url]?.stringValue
    token = object[Key.token]?.stringValue
    sounds = [:]
    for (key, value) in object[Key.sounds]?.objectValue ?? [:] {
      guard let priority = Int(key), Self.priorities.contains(priority) else { continue }
      if case .null = value {
        sounds[priority] = .silent
      } else if let name = value.stringValue {
        sounds[priority] = .named(name)
      }
    }
    dismiss = [:]
    for (key, value) in object[Key.dismiss]?.objectValue ?? [:] {
      guard let priority = Int(key), Self.priorities.contains(priority) else { continue }
      if let seconds = value.numberValue { dismiss[priority] = seconds }
    }
    extraTopics = (object[Key.extraTopics]?.arrayValue ?? []).compactMap(\.stringValue)
    allowInsecure = object[Key.allowInsecure]?.isTrue ?? false
    extras = object.filter { !Self.Key.known.contains($0.key) }
  }

  /// The JSON object to write: extras plus every field that has a value.
  public var object: [String: ConfigValue] {
    var result = extras
    if let url { result[Key.url] = .string(url) }
    if let token { result[Key.token] = .string(token) }
    if !sounds.isEmpty {
      result[Key.sounds] = .object(
        Dictionary(
          uniqueKeysWithValues: sounds.map { priority, sound in
            switch sound {
            case .silent: (String(priority), ConfigValue.null)
            case .named(let name): (String(priority), ConfigValue.string(name))
            }
          }))
    }
    if !dismiss.isEmpty {
      result[Key.dismiss] = .object(
        Dictionary(uniqueKeysWithValues: dismiss.map { (String($0.key), .number($0.value)) }))
    }
    if !extraTopics.isEmpty { result[Key.extraTopics] = .array(extraTopics.map { .string($0) }) }
    if allowInsecure { result[Key.allowInsecure] = .bool(true) }
    return result
  }

  /// Parses file contents; nil when they are empty, malformed or not a JSON object.
  public static func parse(_ data: Data) -> Config? {
    ConfigValue.parseObject(data).map(Config.init(object:))
  }

  /// The bytes to write to the file.
  public func serialized() throws(NtfyError) -> Data {
    try ConfigValue.encodeObject(object)
  }
}
