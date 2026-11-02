import ArgumentParser
import Foundation
import NtfyCore
import NtfyIPC

struct NotifyCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "notify",
    abstract: "Send a local notification through the app (no server needed).",
    discussion: """
      With --json the payload is read from stdin and the result is printed as JSON:
        echo '{"title":"T","body":"B"}' | ntfy-mac notify --json
      """
  )

  @Option(name: .shortAndLong, help: "The notification text.") var message: String?
  @Option(name: .shortAndLong, help: "The title (default: ntfy-mac).") var title: String?
  @Option(name: .shortAndLong, help: "Priority 1-5 (sound and urgency).") var priority: Int?
  @Option(name: .customLong("tag"), help: "An emoji tag name; repeatable.") var tags: [String] = []
  @Option(name: .customLong("url"), help: "Open this URL when the notification is clicked.")
  var url: String?
  @Option(
    name: [.short, .customLong("dismiss-after")],
    help: "Remove the notification after this many seconds (0 keeps it).")
  var dismissAfter: Double?
  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let posted: Bool
    let paused: Bool
  }

  func validate() throws {
    let flagged =
      message != nil || title != nil || priority != nil || !tags.isEmpty || url != nil
      || dismissAfter != nil
    if output.json {
      guard !flagged else {
        throw ValidationError("--json reads the whole payload from stdin; drop the other options.")
      }
      return
    }
    guard let message, !message.isEmpty else {
      throw ValidationError("-m / --message is required (or --json with a payload on stdin).")
    }
    if let priority, !Priority.range.contains(priority) {
      throw ValidationError("Priority must be 1-5 (got \(priority)).")
    }
    if let dismissAfter, !dismissAfter.isFinite || dismissAfter < 0 {
      throw ValidationError("-d / --dismiss-after must be a number of seconds, 0 or more.")
    }
    if let url {
      do {
        _ = try NotifyInput.clickURL(url)
      } catch let failure as CLIFailure {
        throw ValidationError(failure.message)
      }
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let payload = try buildPayload(environment)
    let request = Request(id: UUID().uuidString, command: .notify, notify: payload)
    let response = try await environment.app.send(request, launch: true)
    let posted = try response.requireSuccess()?.notify?.posted ?? true
    out.result(
      Report(posted: posted, paused: !posted),
      text: posted ? "Notification sent." : "Notifications are paused; this one is held back."
    )
  }

  private func buildPayload(_ environment: CLIEnvironment) throws -> NotifyPayload {
    if output.json {
      guard !environment.terminal.stdinIsTTY else {
        throw CLIFailure.usage(
          "--json reads the payload from stdin, but stdin is a terminal. "
            + "Pipe it: echo '{\"body\":\"hi\"}' | ntfy-mac notify --json")
      }
      return try NotifyInput.payload(json: environment.readStandardInput())
    }
    return NotifyPayload(
      title: title ?? NotifyInput.defaultTitle, body: message ?? "",
      priority: priority ?? Priority.default.rawValue, tags: tags,
      clickURL: try url.map(NotifyInput.clickURL), dismissAfterSeconds: dismissAfter)
  }
}
