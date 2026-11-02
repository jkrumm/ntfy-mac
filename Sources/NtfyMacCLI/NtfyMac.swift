import ArgumentParser
import Darwin
import Foundation

@main
struct NtfyMac: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ntfy-mac",
    abstract: "Native ntfy notifications for macOS.",
    discussion: "Every command takes --json for machine-readable output on stdout.",
    subcommands: [
      SetupCommand.self, DoctorCommand.self, SubscribeCommand.self, UnsubscribeCommand.self,
      ConfigCommand.self, NotifyCommand.self, SoundsCommand.self, LogsCommand.self,
      UpdateCommand.self, UninstallCommand.self, VersionCommand.self, StartCommand.self,
      StatusCommand.self, LsCommand.self, SearchCommand.self, ReadCommand.self, AckCommand.self,
      TailCommand.self, WaitCommand.self, PublishCommand.self, PauseCommand.self,
      ResumeCommand.self, LoginItemCommand.self, SchemaCommand.self,
    ]
  )

  /// Replaces ArgumentParser's `main`, which would exit 64 on a usage error.
  static func main() async {
    let status = await CLIEntry.run(
      Array(CommandLine.arguments.dropFirst()), environment: .live(), makeOutput: Output.standard)
    Darwin.exit(status.rawValue)
  }
}
