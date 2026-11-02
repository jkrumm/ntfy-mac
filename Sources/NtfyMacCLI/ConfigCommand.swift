import ArgumentParser
import NtfyCore

struct ConfigCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Show and change notification settings.",
    subcommands: [ConfigSoundsCommand.self, ConfigDismissCommand.self]
  )

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let table = PriorityTable(config: try await environment.config.load())
    out.result(table, text: table.overviewText())
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
