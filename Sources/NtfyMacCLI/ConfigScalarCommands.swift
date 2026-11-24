import ArgumentParser
import NtfyCore

/// The single-value config keys `config get|set|reset` handle.
enum ConfigKey: String, CaseIterable, ExpressibleByArgument {
  case allowInsecure
  case allowPrivateNetworkActions
  case reAlert
  case reAlertIntervalSeconds
  case reAlertMinPriority
  case reAlertMaxRepeats
  case summaryEnabled = "summary.enabled"
  case summaryEndpoint = "summary.endpoint"
  case summaryModel = "summary.model"
  case summaryMinAwayMinutes = "summary.minAwayMinutes"
  case summaryMinMessages = "summary.minMessages"

  /// What `set` accepts, for the usage message.
  var expectation: String {
    switch self {
    case .allowInsecure, .allowPrivateNetworkActions, .reAlert, .summaryEnabled:
      "true, false, on or off"
    case .summaryEndpoint: "an http(s) URL, or an empty value to clear it"
    case .summaryModel: "a model name"
    case .summaryMinAwayMinutes: "a whole number of minutes, 0 or more"
    case .summaryMinMessages: "a whole number above 0"
    case .reAlertIntervalSeconds: "a whole number of seconds above 0"
    case .reAlertMinPriority: "a priority from 1 to 5"
    case .reAlertMaxRepeats: "a whole number, 0 or more"
    }
  }

  /// Validates `text` for this key; throws a usage error naming the key and what it takes.
  func parse(_ text: String) throws -> ScalarValue {
    let invalid = ValidationError("\(rawValue) must be \(expectation) (got \(text)).")
    switch self {
    case .allowInsecure, .allowPrivateNetworkActions, .reAlert, .summaryEnabled:
      return .bool(try Self.flag(text, otherwise: invalid))
    case .summaryEndpoint:
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { return .string("") }
      guard let endpoint = SummaryEndpoint.normalized(trimmed) else { throw invalid }
      return .string(endpoint)
    case .summaryModel:
      let model = text.trimmingCharacters(in: .whitespaces)
      guard !model.isEmpty else { throw invalid }
      return .string(model)
    default:
      guard let number = Int(text), numbers.contains(number) else { throw invalid }
      return .int(number)
    }
  }

  private static func flag(_ text: String, otherwise invalid: ValidationError) throws -> Bool {
    switch text.lowercased() {
    case "true", "on": return true
    case "false", "off": return false
    default: throw invalid
    }
  }

  /// The whole numbers a numeric key takes.
  private var numbers: ClosedRange<Int> {
    switch self {
    case .reAlertIntervalSeconds, .summaryMinMessages: 1...Int.max
    case .reAlertMinPriority: Priority.range
    default: 0...Int.max
    }
  }

  func value(in config: Config) -> ScalarValue {
    switch self {
    case .allowInsecure: .bool(config.allowInsecure)
    case .allowPrivateNetworkActions: .bool(config.allowPrivateNetworkActions)
    case .reAlert: .bool(config.reAlert)
    case .reAlertIntervalSeconds: .int(config.reAlertIntervalSeconds)
    case .reAlertMinPriority: .int(config.reAlertMinPriority)
    case .reAlertMaxRepeats: .int(config.reAlertMaxRepeats)
    case .summaryEnabled, .summaryEndpoint, .summaryModel, .summaryMinAwayMinutes,
      .summaryMinMessages:
      summaryValue(config.summary)
    }
  }

  private func summaryValue(_ summary: SummarySettings) -> ScalarValue {
    switch self {
    case .summaryEnabled: .bool(summary.enabled)
    case .summaryEndpoint: .string(summary.endpoint ?? "")
    case .summaryModel: .string(summary.model)
    case .summaryMinAwayMinutes: .int(summary.minAwayMinutes)
    default: .int(summary.minMessages)
    }
  }

  var defaultValue: ScalarValue { value(in: Config()) }

  func apply(_ value: ScalarValue, to config: inout Config) {
    switch (self, value) {
    case (.allowInsecure, .bool(let flag)): config.allowInsecure = flag
    case (.allowPrivateNetworkActions, .bool(let flag)): config.allowPrivateNetworkActions = flag
    case (.reAlert, .bool(let flag)): config.reAlert = flag
    case (.reAlertIntervalSeconds, .int(let number)): config.reAlertIntervalSeconds = number
    case (.reAlertMinPriority, .int(let number)):
      config.reAlertMinPriority = Priority(clamping: number).rawValue
    case (.reAlertMaxRepeats, .int(let number)): config.reAlertMaxRepeats = number
    default: applySummary(value, to: &config.summary)
    }
  }

  private func applySummary(_ value: ScalarValue, to summary: inout SummarySettings) {
    switch (self, value) {
    case (.summaryEnabled, .bool(let flag)): summary.enabled = flag
    case (.summaryEndpoint, .string(let text)): summary.endpoint = text.isEmpty ? nil : text
    case (.summaryModel, .string(let text)): summary.model = text
    case (.summaryMinAwayMinutes, .int(let number)): summary.minAwayMinutes = number
    case (.summaryMinMessages, .int(let number)): summary.minMessages = number
    default: break
    }
  }
}

enum ScalarValue: Encodable, Sendable, Hashable, CustomStringConvertible {
  case bool(Bool)
  case int(Int)
  case string(String)

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .bool(let flag): try container.encode(flag)
    case .int(let number): try container.encode(number)
    case .string(let text): try container.encode(text)
    }
  }

  var description: String {
    switch self {
    case .bool(let flag): flag ? "true" : "false"
    case .int(let number): String(number)
    case .string(let text): text
    }
  }
}

/// What `config get|set|reset` print.
struct ScalarSetting: Encodable, Sendable {
  let key: String
  let value: ScalarValue
  /// Whether the value is the default.
  let isDefault: Bool

  init(_ key: ConfigKey, value: ScalarValue) {
    self.key = key.rawValue
    self.value = value
    isDefault = value == key.defaultValue
  }

  var text: String { "\(key) = \(value)" + (isDefault ? " (default)" : "") }
}

struct ConfigGet: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "get", abstract: "Print the value of a setting.",
    discussion: "Example: ntfy-mac config get reAlertIntervalSeconds")

  @Argument(help: "The setting.") var key: ConfigKey
  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let config = try await environment.config.load()
    let setting = ScalarSetting(key, value: key.value(in: config))
    out.result(setting, text: setting.text)
  }
}

struct ConfigSet: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "set", abstract: "Change a setting.",
    discussion: """
      Booleans take true, false, on or off. reAlertIntervalSeconds is above 0,
      reAlertMinPriority 1 to 5, reAlertMaxRepeats 0 or more. The running app picks the change up
      through its config watcher.

        ntfy-mac config set reAlert off
        ntfy-mac config set reAlertIntervalSeconds 600
      """)

  @Argument(help: "The setting.") var key: ConfigKey
  @Argument(help: "The new value.") var value: String
  @OptionGroup var output: OutputOptions

  func validate() throws {
    _ = try key.parse(value)
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let parsed = try key.parse(value)
    if key == .summaryEndpoint, case .string(let endpoint) = parsed, !endpoint.isEmpty {
      let allowInsecure = try await environment.config.load().allowInsecure
      guard SummaryEndpoint.isSecure(endpoint, allowInsecure: allowInsecure) else {
        throw CLIFailure.runtime(
          "insecure-server",
          "Refusing a plain http endpoint: the key would travel unprotected. Use https, or "
            + "turn on: ntfy-mac config set allowInsecure true")
      }
    }
    let key = key
    try await environment.config.update { key.apply(parsed, to: &$0) }
    let config = try await environment.config.load()
    let setting = ScalarSetting(key, value: key.value(in: config))
    out.result(setting, text: setting.text)
  }
}

struct ConfigReset: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "reset", abstract: "Restore a setting to its default.",
    discussion: "Example: ntfy-mac config reset reAlertIntervalSeconds")

  @Argument(help: "The setting.") var key: ConfigKey
  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let key = key
    try await environment.config.update { key.apply(key.defaultValue, to: &$0) }
    let setting = ScalarSetting(key, value: key.defaultValue)
    out.result(setting, text: setting.text)
  }
}
