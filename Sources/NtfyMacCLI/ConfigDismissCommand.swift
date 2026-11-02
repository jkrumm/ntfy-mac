import ArgumentParser
import Foundation
import NtfyCore

struct ConfigDismissCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "dismiss",
    abstract: "Show and change the auto-dismiss time per priority.",
    subcommands: [ConfigDismissShow.self, ConfigDismissSet.self, ConfigDismissReset.self]
  )

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await ConfigDismissShow.show(environment, out)
  }
}

struct ConfigDismissShow: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "show", abstract: "Show the auto-dismiss time per priority.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await Self.show(environment, out)
  }

  static func show(_ environment: CLIEnvironment, _ out: Output) async throws {
    let table = PriorityTable(config: try await environment.config.load())
    out.result(table, text: table.dismissText())
  }
}

struct ConfigDismissSet: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "set", abstract: "Set the auto-dismiss time of a priority (seconds, or never).",
    discussion: "Example: ntfy-mac config dismiss set 3 10")

  @Argument(help: "Priority, 1 (min) to 5 (urgent).") var priority: Int
  @Argument(help: "Seconds, or never.") var value: String
  @OptionGroup var output: OutputOptions

  func validate() throws {
    try validatePriority(priority)
    _ = try Self.seconds(from: value)
  }

  /// `never` is 0; anything else must be a finite number of seconds, 0 or more.
  static func seconds(from value: String) throws -> Double {
    if value == "never" { return 0 }
    guard let seconds = Double(value), seconds.isFinite, seconds >= 0 else {
      throw ValidationError("Dismiss time must be a number of seconds (0 or more) or 'never'.")
    }
    return seconds
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let seconds = try Self.seconds(from: value)
    let priority = priority
    let table = try await updatePriorityTable(environment) { $0.dismiss[priority] = seconds }
    let row = PriorityRow(priority: priority, config: Config(dismiss: [priority: seconds]))
    out.result(
      table,
      text:
        "Priority \(row.title) → \(row.dismissText)\nTest it: ntfy-mac notify -m \"test\" -p \(priority)"
    )
  }
}

struct ConfigDismissReset: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "reset", abstract: "Restore the default auto-dismiss times.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let table = try await updatePriorityTable(environment) { $0.dismiss = [:] }
    out.result(
      table, text: "Dismiss configuration reset to defaults.\n\n" + table.dismissText())
  }
}
