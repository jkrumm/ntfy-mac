import ArgumentParser
import NtfyCore

/// One topic's settings as `config topic` prints them.
struct TopicSettingsRow: Encodable, Sendable {
  let topic: String
  let mute: Bool
  let minPriority: Int?
  let emoji: String?

  init(topic: String, settings: TopicSettings) {
    self.topic = topic
    mute = settings.mute
    minPriority = settings.minPriority
    emoji = settings.emoji
  }

  var text: String {
    "\(topic): " + (mute ? "muted" : "notifying")
      + ", minimum priority " + (minPriority.map(String.init) ?? "none")
      + ", emoji " + (emoji ?? "none")
  }
}

struct TopicList: Encodable, Sendable {
  let topics: [TopicSettingsRow]

  init(_ config: Config) {
    topics = config.topicSettings.keys.sorted().map {
      TopicSettingsRow(topic: $0, settings: config.topicSettings[$0] ?? TopicSettings())
    }
  }

  var text: String {
    topics.isEmpty
      ? "No topic has its own settings. Set one with: ntfy-mac config topic set <topic> --mute"
      : topics.map(\.text).joined(separator: "\n")
  }
}

struct ConfigTopicCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "topic", abstract: "Show and change the settings of one topic.",
    discussion: """
      The topic follows the verb: ntfy-mac config topic show|set|reset <topic>. `config topic
      list` shows every topic with settings of its own. A muted topic is stored in the history and
      never notified; a minimum priority holds back messages below it.
      """,
    subcommands: [
      ConfigTopicList.self, ConfigTopicShow.self, ConfigTopicSet.self, ConfigTopicReset.self,
    ])

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await ConfigTopicList.list(environment, out)
  }
}

/// The topic argument shared by `show`, `set` and `reset`.
private func validateTopic(_ topic: String) throws {
  guard TopicResolver.isValid(topic) else {
    throw ValidationError(
      "Invalid topic name \"\(topic)\": use 1-64 letters, digits, '-' or '_'.")
  }
}

struct ConfigTopicList: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List the topics that have settings of their own.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await Self.list(environment, out)
  }

  static func list(_ environment: CLIEnvironment, _ out: Output) async throws {
    let list = TopicList(try await environment.config.load())
    out.result(list, text: list.text)
  }
}

struct ConfigTopicShow: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "show", abstract: "Show the settings of a topic.")

  @Argument(help: "The topic.") var topic: String
  @OptionGroup var output: OutputOptions

  func validate() throws { try validateTopic(topic) }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let config = try await environment.config.load()
    let row = TopicSettingsRow(
      topic: topic, settings: config.topicSettings[topic] ?? TopicSettings())
    out.result(row, text: row.text)
  }
}

struct ConfigTopicSet: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "set", abstract: "Mute a topic, filter it by priority, or give it an emoji.",
    discussion: """
      At least one option is required. --min-priority takes 1 to 5, or none to remove the filter;
      --emoji takes an emoji for the notification title, or none to remove it.

        ntfy-mac config topic set builds --mute
        ntfy-mac config topic set builds --min-priority 4 --emoji 🔨
      """)

  @Argument(help: "The topic.") var topic: String
  @Flag(name: .long, help: "Store messages without notifying.") var mute = false
  @Flag(name: .long, help: "Notify again.") var unmute = false
  @Option(name: .long, help: "Hold back messages below this priority (1-5), or none.")
  var minPriority: String?
  @Option(name: .long, help: "Prefix for the notification title, or none.") var emoji: String?
  @OptionGroup var output: OutputOptions

  func validate() throws {
    try validateTopic(topic)
    guard !(mute && unmute) else {
      throw ValidationError("Use either --mute or --unmute, not both.")
    }
    guard mute || unmute || minPriority != nil || emoji != nil else {
      throw ValidationError("Nothing to set: pass --mute, --unmute, --min-priority or --emoji.")
    }
    _ = try parsedMinPriority()
    _ = try parsedEmoji()
  }

  /// `.some(nil)` is `none`; `nil` leaves the value alone.
  private func parsedMinPriority() throws -> Int?? {
    guard let minPriority else { return nil }
    if minPriority == "none" { return .some(nil) }
    guard let value = Int(minPriority), Priority.range.contains(value) else {
      throw ValidationError("--min-priority must be 1-5 or none (got \(minPriority)).")
    }
    return .some(value)
  }

  private func parsedEmoji() throws -> String?? {
    guard let emoji else { return nil }
    let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "none" { return .some(nil) }
    guard !trimmed.isEmpty else { throw ValidationError("--emoji must not be empty (use none).") }
    return .some(trimmed)
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let minPriority = try parsedMinPriority()
    let emoji = try parsedEmoji()
    let topic = topic
    let mute = mute
    let unmute = unmute
    try await environment.config.update { config in
      var settings = config.topicSettings[topic] ?? TopicSettings()
      if mute { settings.mute = true }
      if unmute { settings.mute = false }
      if let minPriority { settings.minPriority = minPriority }
      if let emoji { settings.emoji = emoji }
      config.topicSettings[topic] = settings == TopicSettings() ? nil : settings
    }
    let config = try await environment.config.load()
    let row = TopicSettingsRow(
      topic: topic, settings: config.topicSettings[topic] ?? TopicSettings())
    out.result(row, text: row.text)
  }
}

struct ConfigTopicReset: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "reset", abstract: "Remove every setting of a topic.")

  @Argument(help: "The topic.") var topic: String
  @OptionGroup var output: OutputOptions

  func validate() throws { try validateTopic(topic) }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let topic = topic
    try await environment.config.update { $0.topicSettings[topic] = nil }
    let row = TopicSettingsRow(topic: topic, settings: TopicSettings())
    out.result(row, text: row.text)
  }
}
