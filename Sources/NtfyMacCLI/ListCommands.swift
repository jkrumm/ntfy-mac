import ArgumentParser
import Foundation
import NtfyCore

struct LsCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "ls", abstract: "List messages from the history, newest first.",
    discussion: """
      Reads the history database directly; the app need not run. With --json the output is an
      array of message objects (topic, id, time, title, message, priority, tags, read,
      acknowledged, click, attachments). An empty or missing history is an empty list.
      """)

  @OptionGroup var filter: HistoryFilterOptions
  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let entries = try await Self.entries(filter, text: nil, environment)
    out.result(entries.map { MessageView($0) }, text: MessageText.table(entries))
  }

  static func entries(
    _ filter: HistoryFilterOptions, text: String?, _ environment: CLIEnvironment
  ) async throws -> [StoredMessage] {
    guard let inbox = try await environment.openHistory() else { return [] }
    return try await filter.fetch(inbox, text: text, now: environment.clock.now())
  }
}

struct SearchCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "search", abstract: "Search the history by text, newest first.",
    discussion: """
      Full-text search over titles and messages; every word matches as a prefix. Takes the same
      filters and prints the same output as ls.
      """)

  @Argument(help: "The words to search for.") var query: String
  @OptionGroup var filter: HistoryFilterOptions
  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ValidationError("The search query must not be empty.")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let entries = try await LsCommand.entries(filter, text: query, environment)
    out.result(entries.map { MessageView($0) }, text: MessageText.table(entries))
  }
}
