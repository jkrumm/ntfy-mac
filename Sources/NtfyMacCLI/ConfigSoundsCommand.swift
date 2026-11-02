import ArgumentParser
import NtfyCore

struct ConfigSoundsCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "sounds",
    abstract: "Show and change the notification sound per priority.",
    subcommands: [
      ConfigSoundsShow.self, ConfigSoundsList.self, ConfigSoundsSet.self, ConfigSoundsReset.self,
    ]
  )

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await ConfigSoundsShow.show(environment, out)
  }
}

struct ConfigSoundsShow: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "show", abstract: "Show the sound per priority.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await Self.show(environment, out)
  }

  static func show(_ environment: CLIEnvironment, _ out: Output) async throws {
    let table = PriorityTable(config: try await environment.config.load())
    out.result(table, text: table.soundsText())
  }
}

struct ConfigSoundsList: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List the sounds that can be chosen.")

  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let sounds: [String]
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let names = SoundCatalog.sounds(in: environment.paths.soundDirectories).map(\.name)
    var lines = ["Available notification sounds:", ""] + names.map { "  \($0)" }
    lines += [
      "", "  (\(SoundCatalog.silent))  — no sound", "", "Found \(names.count) sounds.",
      "Custom sounds can be added to ~/Library/Sounds/ (AIFF/WAV/CAF, max 30s).",
    ]
    out.result(Report(sounds: names + [SoundCatalog.silent]), text: lines.joined(separator: "\n"))
  }
}

struct ConfigSoundsSet: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "set", abstract: "Set the sound of a priority (a sound name, or silent).",
    discussion: "Example: ntfy-mac config sounds set 5 Glass")

  @Argument(help: "Priority, 1 (min) to 5 (urgent).") var priority: Int
  @Argument(help: "A name from `config sounds list`, or silent.") var sound: String
  @OptionGroup var output: OutputOptions

  func validate() throws {
    try validatePriority(priority)
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let value: ConfigSound
    if sound == SoundCatalog.silent {
      value = .silent
    } else {
      let names = SoundCatalog.sounds(in: environment.paths.soundDirectories).map(\.name)
      guard names.contains(sound) else {
        throw CLIFailure.usage(
          "Unknown sound: \(sound). Run 'ntfy-mac config sounds list' to see available sounds.")
      }
      value = .named(sound)
    }
    let priority = priority
    let table = try await updatePriorityTable(environment) { $0.sounds[priority] = value }
    let row = PriorityRow(priority: priority, config: Config(sounds: [priority: value]))
    out.result(
      table,
      text:
        "Priority \(row.title) → \(row.soundText)\nTest it: ntfy-mac notify -m \"test\" -p \(priority)"
    )
  }
}

struct ConfigSoundsReset: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "reset", abstract: "Restore the default sounds.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let table = try await updatePriorityTable(environment) { $0.sounds = [:] }
    out.result(
      table, text: "Sound configuration reset to defaults.\n\n" + table.soundsText())
  }
}
