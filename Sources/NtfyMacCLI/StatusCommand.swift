import ArgumentParser
import Foundation
import NtfyCore
import NtfyIPC

struct StatusCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "status", abstract: "Show the connection, pause, permissions and history counts.",
    discussion: """
      Asks the running app without starting it; if it is down, running is false and everything the
      files know (config, history) is still reported, with exit 0. --require-running exits 4
      instead when the app is not running. With --json every key is always present.
      """)

  @Flag(name: .long, help: "Exit 4 when the app is not running.") var requireRunning = false
  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let info = await appStatus(environment, out)
    let config = try await environment.config.load()
    let now = environment.clock.now()
    let filePause = config.pausedUntil.flatMap { $0 > now ? $0 : nil }
    let pausedUntil = info?.pausedUntil ?? filePause
    let history = try await historyStats(environment)
    let server = try await environment.historyServer()
    let local = Set(config.extraTopics)
      .union(ConfigResolver.topics(from: environment.variables["NTFY_TOPICS"]) ?? [])
    let report = StatusReport(
      running: info != nil, appVersion: info?.appVersion, connection: info?.connection,
      configured: server != nil, server: server,
      topics: local.union(history.topics.map(\.topic)).sorted(), paused: pausedUntil != nil,
      pausedUntil: pausedUntil, permission: info?.permission, history: history)
    out.result(report, text: report.text())
    guard requireRunning, info == nil else { return }
    out.note("The ntfy-mac app is not running. Start it with: ntfy-mac start")
    throw ExitRequest(exit: .appUnavailable)
  }

  /// The app's answer, nil when it is not running or does not answer sensibly.
  private func appStatus(_ environment: CLIEnvironment, _ out: Output) async -> StatusResult? {
    do {
      let request = Request(id: UUID().uuidString, command: .status)
      let response = try await environment.app.send(request, launch: false)
      return try response.requireSuccess()?.status
    } catch NtfyError.appUnavailable {
      return nil
    } catch {
      out.note("Could not read the app's status: \(ErrorReport(error).message)")
      return nil
    }
  }

  private func historyStats(_ environment: CLIEnvironment) async throws -> HistoryStats {
    guard let inbox = try await environment.openHistory() else { return .empty }
    let entries = try await inbox.entries(HistoryQuery(limit: 10_000))
    return HistoryStats(entries)
  }
}
