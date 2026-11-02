import ArgumentParser
import Foundation
import NtfyCore

struct TailCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "tail", abstract: "Print messages as NDJSON, optionally following new ones.",
    discussion: """
      One message object per line (the shape of ls --json), oldest first, whether or not --json
      is given. --follow keeps polling the history database every 500 ms and ends cleanly on
      SIGINT. Messages older than a minute when they are stored (a catch-up after an outage) are
      not followed.
      """)

  @OptionGroup var filter: HistoryFilterOptions
  @Flag(name: [.short, .long], help: "Keep running and print new messages as they arrive.")
  var follow = false
  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let start = environment.clock.now()
    let feed = environment.historyFeed()
    let initial: [StoredMessage]
    if let inbox = try await feed.inbox() {
      initial = try await filter.fetch(inbox, now: start)
    } else {
      initial = []
    }
    for entry in initial.reversed() { out.record(MessageView(entry)) }
    guard follow else { return }
    let follower = HistoryFollower(
      feed: feed, filter: filter.query(now: start), clock: environment.clock, start: start,
      seed: initial)
    try await environment.runUntilInterrupted {
      try await follower.follow { out.record(MessageView($0)) }
    }
  }
}
