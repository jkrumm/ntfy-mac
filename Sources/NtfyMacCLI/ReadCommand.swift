import ArgumentParser
import Foundation
import NtfyCore
import NtfyIPC

struct ReadCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "read", abstract: "Show one message in full and mark it read.",
    discussion: """
      Marking read writes to the history database directly (WAL with a busy timeout, safe next
      to the running app); --no-mark leaves the state alone. An unknown message exits 1 with the
      error code not-found.
      """)

  @Argument(help: "The topic.") var topic: String
  @Argument(help: "The message id.") var id: String
  @Flag(name: .long, help: "Do not mark the message read.") var noMark = false
  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard TopicResolver.isValid(topic) else {
      throw ValidationError("Invalid topic name \"\(topic)\": use 1-64 letters, digits, - or _.")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    guard let inbox = try await environment.openHistory(),
      let entry = try await inbox.message(topic: topic, id: id)
    else {
      throw CLIFailure.runtime("not-found", "No message \(topic)/\(id) in the history.")
    }
    var shown = entry
    if !noMark, !entry.isRead, let server = try await environment.historyServer() {
      try await environment.history.writer(server: server).markRead(topic: topic, id: id)
      shown.readAt = environment.clock.now()
    }
    out.result(MessageView(shown), text: MessageText.full(shown))
  }
}

struct AckCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "ack", abstract: "Acknowledge a message, or every unacknowledged one.",
    discussion: """
      Goes through the app (started if needed): it withdraws the notification and stops its
      re-alerts. ack <topic> <id> acknowledges one message and exits 1 with the error code
      not-found for an unknown one; ack --all [--topic T] acknowledges everything pending.
      """)

  @Argument(help: "The topic.") var topic: String?
  @Argument(help: "The message id.") var id: String?
  @Flag(name: .long, help: "Acknowledge every unacknowledged message.") var all = false
  @Option(name: .customLong("topic"), help: "With --all: only this topic.") var onlyTopic: String?
  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let acknowledged: Int
  }

  func validate() throws {
    if all {
      guard topic == nil, id == nil else {
        throw ValidationError("--all takes no topic or id; narrow it with --topic.")
      }
    } else {
      guard topic != nil, id != nil else {
        throw ValidationError("Pass <topic> <id>, or --all.")
      }
      guard onlyTopic == nil else { throw ValidationError("--topic only goes with --all.") }
    }
    if let name = topic ?? onlyTopic, !TopicResolver.isValid(name) {
      throw ValidationError("Invalid topic name \"\(name)\": use 1-64 letters, digits, - or _.")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    if all {
      let request = Request(
        id: UUID().uuidString, command: .ackAll, ackAll: AckAllPayload(topic: onlyTopic))
      let response = try await environment.app.send(request, launch: true)
      let count = try response.requireSuccess()?.ackAll?.acknowledged ?? 0
      out.result(Report(acknowledged: count), text: "Acknowledged \(count) message(s).")
      return
    }
    guard let topic, let id else { return }
    _ = try await Self.acknowledge(topic: topic, id: id, environment)
    out.result(Report(acknowledged: 1), text: "Acknowledged \(topic)/\(id).")
  }

  /// Acknowledges one message through the app.
  static func acknowledge(
    topic: String, id: String, _ environment: CLIEnvironment
  ) async throws -> ResultPayload? {
    let request = Request(
      id: UUID().uuidString, command: .ack, ack: MessageTarget(topic: topic, id: id))
    return try await environment.app.send(request, launch: true).requireSuccess()
  }
}
