import Foundation
import NtfyCore

/// One line of the Topics section.
public struct TopicRow: Sendable, Hashable, Identifiable {
  public enum Origin: Sendable, Hashable {
    /// Subscribed on the server; read only here.
    case server
    /// Added locally (`subscribe`); can be removed again.
    case local
    /// Known only from the history or from topic settings.
    case seen
  }

  public let name: String
  public let origin: Origin
  /// Also in the local additions, whatever else it is.
  public let isLocal: Bool
  public let settings: TopicSettings

  public var id: String { name }
}

extension SettingsModel {
  /// Server topics in server order, then local additions, then every other topic seen in the
  /// history or in the topic settings, by name.
  public var topicRows: [TopicRow] {
    var rows: [TopicRow] = []
    var seen: Set<String> = []
    func add(_ name: String, _ origin: TopicRow.Origin) {
      guard seen.insert(name).inserted else { return }
      rows.append(
        TopicRow(
          name: name, origin: origin, isLocal: config.extraTopics.contains(name),
          settings: config.topicSettings[name] ?? TopicSettings()))
    }
    for name in serverTopics { add(name, .server) }
    for name in config.extraTopics { add(name, .local) }
    for name in (historyTopics + config.topicSettings.keys).sorted() { add(name, .seen) }
    return rows
  }

  /// Mirrors `ntfy-mac subscribe <topic>`: adds a local topic unless it is already one.
  @discardableResult
  public func subscribe(_ topic: String) async -> Bool {
    let name = topic.trimmingCharacters(in: .whitespacesAndNewlines)
    guard TopicResolver.isValid(name) else {
      refuse("Invalid topic name \u{201C}\(name)\u{201D}: use 1-64 letters, digits, - or _.")
      return false
    }
    guard !config.extraTopics.contains(name) else {
      refuse("Topic \u{201C}\(name)\u{201D} is already subscribed.")
      return false
    }
    await write { if !$0.extraTopics.contains(name) { $0.extraTopics.append(name) } }
    return true
  }

  /// Subscribes to the typed topic and clears the field when it worked.
  public func addTypedTopic() async {
    if await subscribe(newTopicText) { newTopicText = "" }
  }

  /// Mirrors `ntfy-mac unsubscribe <topic>`: only local additions can go; the server's own
  /// subscriptions are managed in the ntfy web app.
  @discardableResult
  public func unsubscribe(_ topic: String) async -> Bool {
    guard config.extraTopics.contains(topic) else {
      refuse(
        "Topic \u{201C}\(topic)\u{201D} is not a local addition. "
          + "Server subscriptions are managed in the ntfy web app.")
      return false
    }
    await write { $0.extraTopics.removeAll { $0 == topic } }
    return true
  }

  public func setMute(_ mute: Bool, topic: String) async {
    await updateTopic(topic) { $0.mute = mute }
  }

  /// `nil` removes the filter.
  public func setMinPriority(_ priority: Int?, topic: String) async {
    let pinned = priority.map { Priority(clamping: $0).rawValue }
    await updateTopic(topic) { $0.minPriority = pinned }
  }

  /// Blank or `nil` removes the emoji.
  public func setEmoji(_ emoji: String?, topic: String) async {
    let trimmed = emoji?.trimmingCharacters(in: .whitespacesAndNewlines)
    await updateTopic(topic) { $0.emoji = trimmed.flatMap { $0.isEmpty ? nil : $0 } }
  }

  /// Like `config topic reset <topic>`.
  public func resetTopic(_ topic: String) async {
    await write { $0.topicSettings[topic] = nil }
  }

  private func updateTopic(
    _ topic: String, _ change: @escaping @Sendable (inout TopicSettings) -> Void
  ) async {
    await write { config in
      var settings = config.topicSettings[topic] ?? TopicSettings()
      change(&settings)
      config.topicSettings[topic] = settings == TopicSettings() ? nil : settings
    }
  }
}
