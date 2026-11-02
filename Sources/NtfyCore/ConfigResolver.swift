import Foundation

/// The environment variables the config honours.
public struct ConfigEnvironment: Sendable, Hashable {
  public var url: String?
  public var token: String?
  /// Raw `NTFY_TOPICS`.
  public var topics: String?

  public init(url: String? = nil, token: String? = nil, topics: String? = nil) {
    self.url = url
    self.token = token
    self.topics = topics
  }

  public init(_ environment: [String: String]) {
    self.init(
      url: environment["NTFY_URL"], token: environment["NTFY_TOKEN"],
      topics: environment["NTFY_TOPICS"])
  }
}

/// A configured value that cannot be used. The message says what to fix.
public enum ConfigError: Error, Sendable, Hashable, CustomStringConvertible {
  case invalidURL(String)
  case unsupportedScheme(String)
  case emptyToken

  public var description: String {
    switch self {
    case .invalidURL(let url): "Invalid NTFY URL: \(url)"
    case .unsupportedScheme(let scheme):
      "Invalid NTFY URL protocol: \(scheme). Must be http or https."
    case .emptyToken: "NTFY token must not be empty."
    }
  }
}

/// Validated settings, ready for the stream and the notifier.
public struct Settings: Sendable, Hashable {
  /// Scheme and host checked, one trailing slash stripped.
  public var url: URL
  /// Trimmed, non-empty.
  public var token: String
  /// `NTFY_TOPICS` when set: it replaces topic auto-discovery entirely. Nil means discover.
  public var topics: [String]?
  /// Merged with the discovered topics.
  public var extraTopics: [String]
  public var sounds: [Int: ConfigSound]
  public var dismiss: [Int: Double]
  /// Passed on to the clients; see `Config.allowInsecure`.
  public var allowInsecure: Bool

  public init(
    url: URL, token: String, topics: [String]? = nil, extraTopics: [String] = [],
    sounds: [Int: ConfigSound] = [:], dismiss: [Int: Double] = [:], allowInsecure: Bool = false
  ) {
    self.allowInsecure = allowInsecure
    self.url = url
    self.token = token
    self.topics = topics
    self.extraTopics = extraTopics
    self.sounds = sounds
    self.dismiss = dismiss
  }
}

public enum SettingsResolution: Sendable, Hashable {
  case configured(Settings)
  /// No URL or no token anywhere. A normal first-run state, not an error.
  case notConfigured
}

/// Pure merge of file, Keychain and environment into `Settings`.
public enum ConfigResolver {
  /// - The file wins over `NTFY_URL` and `NTFY_TOKEN`, which only fill what it lacks. That is
  ///   the 1.x behaviour and part of the compatibility contract, so it stays.
  /// - Token: Keychain, then the legacy plaintext token in the file, then `NTFY_TOKEN`.
  /// - An empty string counts as missing, as in 1.x. A blank token or a bad URL throws.
  public static func resolve(
    config: Config, keychainToken: String?, environment: ConfigEnvironment
  ) throws(ConfigError) -> SettingsResolution {
    let url = firstNonEmpty(config.url, environment.url)
    let token = firstNonEmpty(keychainToken, config.token, environment.token)
    guard let url, let token else { return .notConfigured }
    return .configured(
      Settings(
        url: try validated(url: url),
        token: try validated(token: token),
        topics: topics(from: environment.topics),
        extraTopics: config.extraTopics,
        sounds: config.sounds,
        dismiss: config.dismiss,
        allowInsecure: config.allowInsecure))
  }

  /// Comma-separated, trimmed, empties dropped. Nil when unset or empty, so discovery stays on.
  public static func topics(from raw: String?) -> [String]? {
    guard let raw, !raw.isEmpty else { return nil }
    return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private static func firstNonEmpty(_ values: String?...) -> String? {
    values.lazy.compactMap { $0 }.first { !$0.isEmpty }
  }

  private static func validated(url raw: String) throws(ConfigError) -> URL {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let stripped = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    guard let url = URL(string: stripped), let scheme = url.scheme?.lowercased() else {
      throw .invalidURL(raw)
    }
    guard scheme == "http" || scheme == "https" else { throw .unsupportedScheme(scheme + ":") }
    guard let host = url.host(), !host.isEmpty else { throw .invalidURL(raw) }
    return url
  }

  private static func validated(token raw: String) throws(ConfigError) -> String {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { throw .emptyToken }
    return token
  }
}
