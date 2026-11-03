import Foundation
import NtfyCore

/// Where the composer stands. A failed send keeps the draft, so the text is never lost.
public enum ComposerState: Sendable, Hashable {
  case idle
  case sending
  case failed(String)
}

/// Whether the composer can be used, and for which topic.
public enum ComposerAvailability: Sendable, Hashable {
  case ready(topic: String)
  /// No topic has messages or is subscribed, so there is nowhere to send to.
  case noTopic

  /// What the disabled composer says.
  public var explanation: String? {
    switch self {
    case .ready: nil
    case .noTopic: "There is no topic to send to yet. Subscribe to one in Settings."
    }
  }
}

/// What the server settings allow right now.
public enum PublisherResolution: Sendable {
  case ready(any NtfyPublishing)
  case notConfigured
  /// The settings exist but cannot be used (a bad URL, an empty token); the text says what to fix.
  case invalid(String)
}

/// Where the composer gets a publisher from. Resolved on every send, so a changed server or
/// token applies without rebuilding the window. The app root implements it over the config and
/// the Keychain, the same settings `ntfy-mac publish` resolves.
public protocol PublisherProviding: Sendable {
  func resolve() async throws(NtfyError) -> PublisherResolution
}

/// The words for a failed send.
public enum ComposerErrorText {
  public static let notConfigured = "No server is set up yet. Add one in Settings."

  public static func describe(_ error: NtfyError) -> String {
    switch error {
    case .unauthorized:
      "The server rejected the token. Check it in Settings."
    case .serverUnreachable:
      "The server could not be reached. The message is still in the box."
    case .rateLimited(let retryAfter):
      retryAfter.map { "The server is throttling messages. Try again in \($0) seconds." }
        ?? "The server is throttling messages. Try again in a moment."
    case .redirected:
      "The server redirected the request. Fix the server URL in Settings."
    case .insecureServer:
      "The token would travel over plain http. Use https in Settings."
    case .invalidTopic(let name):
      "\u{201C}\(name)\u{201D} is not a topic name the server accepts."
    case .invalidResponse:
      "The server's answer made no sense. The message may or may not have arrived."
    case .storage(let detail):
      "The settings could not be read: \(detail)"
    case .appUnavailable, .permissionDenied:
      "The message could not be sent."
    }
  }
}
