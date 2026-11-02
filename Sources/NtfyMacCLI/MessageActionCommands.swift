import ArgumentParser
import Foundation
import NtfyCore
import NtfyIPC

private func validateTopic(_ name: String) throws {
  guard TopicResolver.isValid(name) else {
    throw ValidationError("Invalid topic name \"\(name)\": use 1-64 letters, digits, - or _.")
  }
}

struct RemindCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "remind", abstract: "Show a message again later.",
    discussion: """
      Goes through the app (started if needed): the message is shown again as a notification
      when the time comes (the app checks every 30 seconds). Pass --in with a duration (s, m,
      h and d, alone or combined: 15m, 1h, 1h30m) or --until with an ISO 8601 time in the
      future. An unknown message exits 1 with the error code not-found.
      """)

  @Argument(help: "The topic.") var topic: String
  @Argument(help: "The message id.") var id: String
  @Option(name: .customLong("in"), help: "Remind after this long, like 15m, 1h or 1d.")
  var delay: String?
  @Option(name: .long, help: "Remind at this ISO 8601 time.") var until: String?
  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let topic: String
    let id: String
    let remindAt: Date
  }

  func validate() throws {
    try validateTopic(topic)
    guard (delay == nil) != (until == nil) else {
      throw ValidationError("Use exactly one of --in or --until.")
    }
    if let delay, DurationParser.seconds(delay) == nil {
      throw ValidationError("--in must look like 15m, 1h, 1d or 1h30m (got \(delay)).")
    }
    if let until, TimePoint.iso8601(until) == nil {
      throw ValidationError("--until must be an ISO 8601 time (got \(until)).")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let now = environment.clock.now()
    let when = try time(now: now)
    let payload = RemindPayload(topic: topic, id: id, until: when)
    let request = Request(id: UUID().uuidString, command: .remind, remind: payload)
    _ = try await environment.app.send(request, launch: true).requireSuccess()
    out.result(
      Report(topic: topic, id: id, remindAt: when),
      text: "Will remind about \(topic)/\(id) at \(MessageText.timestamp(when)).")
  }

  private func time(now: Date) throws -> Date {
    if let delay, let seconds = DurationParser.seconds(delay) {
      return now.addingTimeInterval(seconds)
    }
    if let until, let date = TimePoint.iso8601(until) {
      guard date > now else { throw CLIFailure.usage("--until must be in the future.") }
      return date
    }
    throw CLIFailure.usage("Use exactly one of --in or --until.")
  }
}

struct DeleteCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "delete", abstract: "Delete a message, or every message of a topic.",
    discussion: """
      Goes through the app (started if needed): the message leaves the history, its
      notification and re-alerts stop, and it is never shown again. delete <topic> <id> removes
      one message and exits 1 with the error code not-found for an unknown one;
      delete --topic T --all removes the whole topic. There is no undo and no prompt. An app
      from before this command exists answers with the error code app-outdated.
      """)

  @Argument(help: "The topic.") var topic: String?
  @Argument(help: "The message id.") var id: String?
  @Flag(name: .long, help: "Delete every message of --topic.") var all = false
  @Option(name: .customLong("topic"), help: "With --all: the topic to empty.") var onlyTopic:
    String?
  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let deleted: Int
  }

  func validate() throws {
    if all {
      guard topic == nil, id == nil else {
        throw ValidationError("--all takes no topic or id; name the topic with --topic.")
      }
      guard let onlyTopic else { throw ValidationError("--all needs --topic <topic>.") }
      try validateTopic(onlyTopic)
    } else {
      guard let topic, id != nil else {
        throw ValidationError("Pass <topic> <id>, or --topic <topic> --all.")
      }
      guard onlyTopic == nil else { throw ValidationError("--topic only goes with --all.") }
      try validateTopic(topic)
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    guard let name = all ? onlyTopic : topic else { return }
    let request = Request(
      id: UUID().uuidString, command: .delete,
      delete: DeletePayload(topic: name, id: all ? nil : id))
    let response = try await environment.app.send(request, launch: true)
    if response.status == .error, response.code == .badRequest,
      response.message == IPC.invalidFrameMessage
    {
      throw CLIFailure.runtime(
        "app-outdated",
        "The running ntfy-mac app is too old to delete messages. Update it, then run: ntfy-mac start"
      )
    }
    let deleted = try response.requireSuccess()?.delete?.deleted ?? 0
    out.result(
      Report(deleted: deleted),
      text: all
        ? "Deleted \(deleted) message(s) of \(name)." : "Deleted \(name)/\(id ?? "")."
    )
  }
}
