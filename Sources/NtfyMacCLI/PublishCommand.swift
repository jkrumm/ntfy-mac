import ArgumentParser
import Foundation
import NtfyCore

struct PublishCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "publish", abstract: "Publish a message to a topic on the ntfy server.",
    discussion: """
      Sends the message with the configured token (never over plain http unless allowInsecure is
      set). -m - reads the message from stdin. Prints the id and time the server assigned.
        echo "build done" | ntfy-mac publish builds -m - -t CI -p 4 --tag white_check_mark
      """)

  @Argument(help: "The topic to publish to.") var topic: String
  @Option(name: .shortAndLong, help: "The message text, or - to read stdin.") var message: String
  @Option(name: .shortAndLong, help: "The title.") var title: String?
  @Option(name: .shortAndLong, help: "Priority 1-5.") var priority: Int?
  @Option(name: .customLong("tag"), help: "An emoji tag name; repeatable.") var tags: [String] = []
  @Option(name: .long, help: "Open this URL when the notification is clicked.") var click: String?
  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let id: String
    let topic: String
    let time: Date
  }

  func validate() throws {
    guard TopicResolver.isValid(topic) else {
      throw ValidationError("Invalid topic name \"\(topic)\": use 1-64 letters, digits, - or _.")
    }
    guard !message.isEmpty else { throw ValidationError("-m / --message must not be empty.") }
    if let priority, !Priority.range.contains(priority) {
      throw ValidationError("Priority must be 1-5 (got \(priority)).")
    }
    if let click {
      do {
        _ = try NotifyInput.clickURL(click)
      } catch let failure as CLIFailure {
        throw ValidationError(failure.message)
      }
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let text = try body(environment)
    let settings = try await environment.settings()
    let publisher = environment.publisher(settings.url, settings.token, settings.allowInsecure)
    let sent = try await publisher.publish(
      PublishRequest(
        topic: topic, message: text, title: title,
        priority: priority.flatMap(Priority.init(rawValue:)),
        tags: tags, click: try click.map(NotifyInput.clickURL)))
    out.result(
      Report(id: sent.id, topic: sent.topic, time: sent.time),
      text: "Published \(sent.topic)/\(sent.id).")
  }

  private func body(_ environment: CLIEnvironment) throws -> String {
    guard message == "-" else { return message }
    guard !environment.terminal.stdinIsTTY else {
      throw CLIFailure.usage("-m - reads the message from stdin, but stdin is a terminal.")
    }
    var text = String(bytes: environment.readStandardInput(), encoding: .utf8) ?? ""
    while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
    guard !text.isEmpty else { throw CLIFailure.usage("The message on stdin is empty.") }
    return text
  }
}
