import Foundation

/// What the app root does after the settings were resolved again.
public enum PipelineReload: Sendable, Hashable {
  /// The running pipeline (or the idle state) stays as it is.
  case keep
  /// Tear down what runs, then build a new pipeline from the settings.
  case rebuild
  /// Tear down what runs; nothing is configured.
  case idle

  /// Decides from the settings the pipeline was built with and the freshly resolved ones. Only
  /// what the connection depends on forces a rebuild; sounds, dismiss times and the re-alert
  /// options are read per notification and never do.
  public static func decide(current: Settings?, resolved: Settings?) -> PipelineReload {
    switch (current, resolved) {
    case (nil, nil): .keep
    case (nil, .some): .rebuild
    case (.some, nil): .idle
    case (let old?, let new?): old.connection == new.connection ? .keep : .rebuild
    }
  }
}

/// The part of `Settings` a running pipeline is built from.
public struct SettingsConnection: Sendable, Hashable {
  public let url: URL
  public let token: String
  public let topics: [String]?
  public let extraTopics: [String]
  public let allowInsecure: Bool
}

extension Settings {
  public var connection: SettingsConnection {
    SettingsConnection(
      url: url, token: token, topics: topics, extraTopics: extraTopics,
      allowInsecure: allowInsecure)
  }

  /// `scheme://host[:port]` in lower case, the key the history stores a server under.
  public var origin: String {
    let scheme = url.scheme?.lowercased() ?? "https"
    let host = url.host()?.lowercased() ?? ""
    guard let port = url.port else { return "\(scheme)://\(host)" }
    return "\(scheme)://\(host):\(port)"
  }

  /// The topic selection for the stream supervisor.
  public var topicSelection: TopicSelection {
    TopicSelection(override: topics, extra: extraTopics)
  }
}
