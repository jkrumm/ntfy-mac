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

  /// What `set` accepts, for the usage message.
  var expectation: String {
    switch self {
    case .allowInsecure, .allowPrivateNetworkActions, .reAlert:
      "true, false, on or off"
    case .reAlertIntervalSeconds: "a whole number of seconds above 0"
    case .reAlertMinPriority: "a priority from 1 to 5"
    case .reAlertMaxRepeats: "a whole number, 0 or more"
    }
  }

  /// Validates `text` for this key; throws a usage error naming the key and what it takes.
  func parse(_ text: String) throws -> ScalarValue {
    let invalid = ValidationError("\(rawValue) must be \(expectation) (got \(text)).")
    switch self {
    case .allowInsecure, .allowPrivateNetworkActions, .reAlert:
      switch text.lowercased() {
      case "true", "on": return .bool(true)
      case "false", "off": return .bool(false)
      default: throw invalid
      }
    case .reAlertIntervalSeconds:
      guard let seconds = Int(text), seconds > 0 else { throw invalid }
      return .int(seconds)
    case .reAlertMinPriority:
      guard let priority = Int(text), Priority.range.contains(priority) else { throw invalid }
      return .int(priority)
    case .reAlertMaxRepeats:
      guard let repeats = Int(text), repeats >= 0 else { throw invalid }
      return .int(repeats)
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
    default: break
    }
  }
}

enum ScalarValue: Encodable, Sendable, Hashable, CustomStringConvertible {
  case bool(Bool)
  case int(Int)

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .bool(let flag): try container.encode(flag)
    case .int(let number): try container.encode(number)
    }
  }

  var description: String {
    switch self {
    case .bool(let flag): flag ? "true" : "false"
    case .int(let number): String(number)
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
