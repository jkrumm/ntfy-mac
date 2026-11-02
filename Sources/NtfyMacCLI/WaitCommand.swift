import ArgumentParser
import Foundation
import NtfyCore

struct WaitCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "wait", abstract: "Block until a matching message arrives.",
    discussion: """
      For scripts and agents waiting on a human. Only messages that arrive after the command
      started count. --match is a case-insensitive substring of title or message, or /regex/
      (/regex/i ignores case). Exit 0 prints the message; no match within --timeout seconds
      exits 1 with the error code timeout. --ack acknowledges the match through the app after
      it is printed.
      """)

  static let defaultTimeout = 300.0

  @Option(name: .long, help: "The topic to watch.") var topic: String
  @Option(name: .long, help: "A substring, or /regex/, to find in the title or message.")
  var match: String
  @Option(name: .long, help: "Give up after this many seconds (default 300).")
  var timeout: Double = Self.defaultTimeout
  @Option(name: .long, help: "Only messages with at least this priority (1-5).")
  var minPriority: Int?
  @Flag(name: .long, help: "Acknowledge the matching message.") var ack = false
  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard TopicResolver.isValid(topic) else {
      throw ValidationError("Invalid topic name \"\(topic)\": use 1-64 letters, digits, - or _.")
    }
    _ = try MessageMatcher(match)
    if let minPriority, !Priority.range.contains(minPriority) {
      throw ValidationError("--min-priority must be 1-5 (got \(minPriority)).")
    }
    guard timeout.isFinite, timeout > 0 else {
      throw ValidationError("--timeout must be a number of seconds above 0 (got \(timeout)).")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let matcher = try MessageMatcher(match)
    let start = environment.clock.now()
    let follower = HistoryFollower(
      feed: environment.historyFeed(),
      filter: HistoryQuery(
        topic: topic, minPriority: minPriority.flatMap(Priority.init(rawValue:))),
      clock: environment.clock, start: start)
    // What is already there never matches: it is marked seen before the real wait begins.
    _ = try await follower.poll()
    let deadline = start.addingTimeInterval(timeout)
    guard
      let found = try await follower.firstMatch(
        until: deadline, where: { matcher.matches($0.message) })
    else {
      throw CLIFailure.runtime(
        "timeout", "No message on \(topic) matched \"\(match)\" within \(Int(timeout.rounded())) s."
      )
    }
    out.result(MessageView(found), text: MessageText.full(found))
    if ack { _ = try await AckCommand.acknowledge(topic: topic, id: found.message.id, environment) }
  }
}
