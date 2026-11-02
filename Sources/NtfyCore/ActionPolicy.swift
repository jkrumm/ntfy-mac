import Foundation

/// What may happen when a message action is run.
public enum ActionDecision: Sendable, Hashable {
  case allow
  /// Ask the user first; the reason is shown in the prompt.
  case confirm(String)
  case deny(String)
}

/// Safety gate for actions a remote sender attached to a message.
public enum ActionPolicy {
  public static func evaluate(_ action: MessageAction, config: Config) -> ActionDecision {
    switch action.kind {
    case .view: evaluateView(action)
    case .http: evaluateHTTP(action, config: config)
    case .broadcast, .copy, .unknown: .deny("unsupported action")
    }
  }

  private static func evaluateView(_ action: MessageAction) -> ActionDecision {
    guard let url = action.url, URLPolicy.openable(url) != nil else {
      return .deny("link cannot be opened")
    }
    return .allow
  }

  private static func evaluateHTTP(_ action: MessageAction, config: Config) -> ActionDecision {
    guard let url = action.url, let scheme = url.scheme?.lowercased() else {
      return .deny("request has no target")
    }
    guard scheme == "http" || scheme == "https" else {
      return .confirm("request uses the \(scheme) scheme")
    }
    guard let host = url.host(), !host.isEmpty else { return .deny("request has no host") }
    if NetworkHost.isPrivate(host), !config.allowPrivateNetworkActions {
      return .confirm("request targets a private network address (\(host))")
    }
    return .allow
  }
}
