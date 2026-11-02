import ArgumentParser
import NtfyCore

struct SubscribeCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "subscribe", abstract: "Show the subscribed topics, add a local one, or reset.",
    discussion: "subscribe <topic> adds a topic; subscribe reset clears the local additions.")

  @Argument(help: "A topic to add, or `reset`.") var topic: String?
  @OptionGroup var output: OutputOptions

  static let reset = "reset"

  private struct Added: Encodable {
    let topic: String
    let added: Bool
  }

  private struct Cleared: Encodable {
    let cleared = true
  }

  func validate() throws {
    guard let topic, topic != Self.reset, !TopicResolver.isValid(topic) else { return }
    throw ValidationError(
      "Invalid topic name \"\(topic)\": use 1-64 letters, digits, '-' or '_'.")
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    switch topic {
    case nil: try await TopicListing(environment, out).show()
    case Self.reset?:
      try await environment.config.update { $0.extraTopics = [] }
      out.result(
        Cleared(), text: "Local topic additions cleared. Only the server's topics are used now.")
    case let name?: try await add(name, environment, out)
    }
  }

  private func add(_ name: String, _ environment: CLIEnvironment, _ out: Output) async throws {
    let existing = try await environment.config.load().extraTopics
    guard !existing.contains(name) else {
      out.result(Added(topic: name, added: false), text: "Topic \"\(name)\" is already subscribed.")
      return
    }
    try await environment.config.update { config in
      if !config.extraTopics.contains(name) { config.extraTopics.append(name) }
    }
    out.result(Added(topic: name, added: true), text: "Subscribed to \"\(name)\".")
  }
}

struct UnsubscribeCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "unsubscribe", abstract: "Remove a locally added topic.")

  @Argument(help: "The topic to remove.") var topic: String
  @OptionGroup var output: OutputOptions

  private struct Removed: Encodable {
    let topic: String
    let removed = true
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let existing = try await environment.config.load().extraTopics
    guard existing.contains(topic) else {
      throw CLIFailure.runtime(
        "topic-not-local",
        "Topic \"\(topic)\" is not in the local additions. "
          + "Server-side subscriptions are managed in the ntfy web UI.")
    }
    let name = topic
    try await environment.config.update { $0.extraTopics.removeAll { $0 == name } }
    out.result(Removed(topic: name), text: "Unsubscribed from \"\(name)\".")
  }
}
