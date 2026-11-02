import ArgumentParser
import Foundation
import NtfyCore
import NtfyIPC

struct StartCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "start", abstract: "Start the ntfy-mac app if it is not running.")

  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let running: Bool
    let started: Bool
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let ping = Request(id: UUID().uuidString, command: .ping)
    do {
      _ = try await environment.app.send(ping, launch: false)
      out.result(Report(running: true, started: false), text: "ntfy-mac is already running.")
    } catch .appUnavailable {
      out.note("Starting the ntfy-mac app...")
      _ = try await environment.app.send(ping, launch: true)
      out.result(Report(running: true, started: true), text: "ntfy-mac started.")
    }
  }
}
