import ArgumentParser
import NtfyCore

@main
struct NtfyMac: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ntfy-mac",
    abstract: "Native ntfy notifications for macOS.",
    version: Version.current,
    subcommands: [VersionCommand.self]
  )
}

struct VersionCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "version",
    abstract: "Print the version."
  )

  func run() {
    print(Version.current)
  }
}
