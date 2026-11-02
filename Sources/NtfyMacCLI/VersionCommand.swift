import ArgumentParser
import NtfyCore

struct VersionCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "version", abstract: "Print the version.")

  @OptionGroup var output: OutputOptions

  private struct Report: Encodable { let version: String }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    out.result(Report(version: Version.current), text: Version.banner())
  }
}
