import ArgumentParser
import NtfyCore

struct ConfigCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Show and change notification settings.",
    subcommands: [
      ConfigShowCommand.self, ConfigSoundsCommand.self, ConfigDismissCommand.self,
      ConfigGet.self, ConfigSet.self, ConfigReset.self, ConfigTopicCommand.self,
      ConfigQuietHoursCommand.self, ConfigMeetingCommand.self,
    ]
  )

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await ConfigShowCommand.show(environment, out)
  }
}

struct ConfigShowCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "show", abstract: "Show every notification setting.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await Self.show(environment, out)
  }

  static func show(_ environment: CLIEnvironment, _ out: Output) async throws {
    let overview = ConfigOverview(config: try await environment.config.load())
    out.result(overview, text: overview.text)
  }
}

/// Everything `config` prints: the priority table plus the scalar settings, the topics with
/// settings of their own and the quiet-hours schedule.
struct ConfigOverview: Encodable, Sendable {
  let priorities: [PriorityRow]
  let settings: [ScalarSetting]
  let topics: [TopicSettingsRow]
  let quietHours: QuietHoursReport
  private let table: PriorityTable

  private enum CodingKeys: String, CodingKey { case priorities, settings, topics, quietHours }

  init(config: Config) {
    table = PriorityTable(config: config)
    priorities = table.priorities
    settings = ConfigKey.allCases.map { ScalarSetting($0, value: $0.value(in: config)) }
    topics = TopicList(config).topics
    quietHours = QuietHoursReport(config.quietHours)
  }

  var text: String {
    var lines = [table.overviewText(), "", "Settings (ntfy-mac config set <key> <value>)", ""]
    lines += settings.map { "  " + $0.text }
    lines += ["", "Topics (ntfy-mac config topic set <topic> ...)", ""]
    lines += topics.isEmpty ? ["  none"] : topics.map { "  " + $0.text }
    lines += ["", quietHours.text]
    return lines.joined(separator: "\n")
  }
}

/// The priority argument of the `set` subcommands.
func validatePriority(_ value: Int) throws {
  guard Priority.range.contains(value) else {
    throw ValidationError("Priority must be 1-5 (got \(value)).")
  }
}

/// Applies a change to the config and returns the resulting table.
func updatePriorityTable(
  _ environment: CLIEnvironment, _ change: @Sendable (inout Config) -> Void
) async throws -> PriorityTable {
  try await environment.config.update(change)
  return PriorityTable(config: try await environment.config.load())
}
