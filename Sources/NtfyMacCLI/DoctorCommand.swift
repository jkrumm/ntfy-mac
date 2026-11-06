import ArgumentParser
import Foundation
import NtfyCore

struct DoctorCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor", abstract: "Check configuration, server, app and permissions.",
    discussion: """
      Read-only: it never changes the install and posts nothing unless --send-test is given.
      The exit code is non-zero when a check fails (3 auth, 4 app or permission, 7 server).
      """)

  @Flag(name: .long, help: "Also post a test notification through the app.") var sendTest = false
  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let checks = await DoctorChecks(environment: environment).run(sendTest: sendTest)
    let report = DoctorReport(
      installChannel: InstallChannel.detect(executablePath: environment.executablePath),
      checks: checks)
    out.result(report, text: report.text())
    if report.exit != .success { throw ExitRequest(exit: report.exit) }
  }
}
