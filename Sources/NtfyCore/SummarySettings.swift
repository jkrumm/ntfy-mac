import Foundation

/// The `summary` group of the config file: the optional "while you were away" digest.
///
/// Off by default. The API key is not here; it lives in the Keychain (`SummaryKey`).
public struct SummarySettings: Sendable, Hashable {
  public static let defaultModel = "claude-haiku-5-5"
  public static let defaultMinAwayMinutes = 15
  public static let defaultMinMessages = 3

  public var enabled: Bool
  /// Base URL of an Anthropic-compatible API (`https://api.anthropic.com`, or a gateway prefix
  /// such as `https://gateway.example.com/anthropic`); `/v1/messages` is appended.
  public var endpoint: String?
  public var model: String
  /// Away for at least this long (or not looked at for this long), then summarize.
  public var minAwayMinutes: Int
  /// Fewer messages than this get no digest.
  public var minMessages: Int

  public init(
    enabled: Bool = false, endpoint: String? = nil, model: String = defaultModel,
    minAwayMinutes: Int = defaultMinAwayMinutes, minMessages: Int = defaultMinMessages
  ) {
    self.enabled = enabled
    self.endpoint = endpoint
    self.model = model
    self.minAwayMinutes = max(0, minAwayMinutes)
    self.minMessages = max(1, minMessages)
  }

  private enum Key {
    static let enabled = "enabled"
    static let endpoint = "endpoint"
    static let model = "model"
    static let minAwayMinutes = "minAwayMinutes"
    static let minMessages = "minMessages"
  }

  /// The digest is switched on and has somewhere to ask. The key is a separate question.
  public var isConfigured: Bool { enabled && !(endpoint?.isEmpty ?? true) }

  /// Reads the `summary` object; wrong-typed or unknown fields read as their default.
  init(value: ConfigValue?) {
    let object = value?.objectValue ?? [:]
    let endpoint = object[Key.endpoint]?.stringValue?.trimmingCharacters(in: .whitespaces)
    let model = object[Key.model]?.stringValue?.trimmingCharacters(in: .whitespaces)
    self.init(
      enabled: object[Key.enabled]?.isTrue ?? false,
      endpoint: endpoint.flatMap { $0.isEmpty ? nil : $0 },
      model: model.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultModel,
      minAwayMinutes: object[Key.minAwayMinutes]?.intValue ?? Self.defaultMinAwayMinutes,
      minMessages: object[Key.minMessages]?.intValue ?? Self.defaultMinMessages)
  }

  /// The JSON to write, or nil when every field is at its default.
  var configValue: ConfigValue? {
    var object: [String: ConfigValue] = [:]
    if enabled { object[Key.enabled] = .bool(true) }
    if let endpoint, !endpoint.isEmpty { object[Key.endpoint] = .string(endpoint) }
    if model != Self.defaultModel { object[Key.model] = .string(model) }
    if minAwayMinutes != Self.defaultMinAwayMinutes {
      object[Key.minAwayMinutes] = .int(minAwayMinutes)
    }
    if minMessages != Self.defaultMinMessages { object[Key.minMessages] = .int(minMessages) }
    return object.isEmpty ? nil : .object(object)
  }
}

/// What a summary endpoint address may look like.
public enum SummaryEndpoint {
  /// The address as stored: trimmed, without trailing slashes or a pasted `/v1/messages`. Nil for
  /// anything that is not an http(s) URL with a host.
  public static func normalized(_ text: String) -> String? {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    if value.hasSuffix("/v1/messages") { value.removeLast("/v1/messages".count) }
    while value.hasSuffix("/") { value.removeLast() }
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", let host = url.host(), !host.isEmpty
    else { return nil }
    return value
  }

  /// Whether the key may travel to this address: https, loopback, or the explicit opt-in.
  public static func isSecure(_ text: String, allowInsecure: Bool) -> Bool {
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
    if scheme == "https" || allowInsecure { return true }
    return ["localhost", "127.0.0.1", "::1"].contains(url.host()?.lowercased() ?? "")
  }
}
