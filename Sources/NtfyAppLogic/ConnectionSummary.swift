import Foundation
import NtfyCore

/// The connection as the UI shows it: a small closed set instead of the supervisor's machine
/// states. A pause the user chose is not part of it; it is `AppModel.pausedUntil`, because
/// notifications are held while the stream stays connected.
public enum ConnectionSummary: Sendable, Hashable {
  /// The local pipeline runs: `notify` works, nothing is streamed.
  case notConfigured
  /// Not started yet, starting, or waiting for a pipeline.
  case connecting
  case connected
  /// Waiting to retry after a failure; `attempt` counts consecutive failures.
  case retrying(until: Date, attempt: Int)
  /// No network path.
  case offline
  /// The Mac is going to sleep.
  case sleeping
  /// Retrying cannot fix it: the user has to act (credentials, server address).
  case needsAttention(reason: String)

  public init(_ status: ConnectionStatus) {
    switch status {
    case .stopped, .connecting: self = .connecting
    case .connected: self = .connected
    case .backingOff(let until, let attempt): self = .retrying(until: until, attempt: attempt)
    case .offline: self = .offline
    case .paused: self = .sleeping
    case .halted(let error): self = .needsAttention(reason: Self.reason(for: error))
    }
  }

  /// One line for the status row.
  public var title: String {
    switch self {
    case .notConfigured: "No server configured"
    case .connecting: "Connecting"
    case .connected: "Connected"
    case .retrying: "Reconnecting"
    case .offline: "Offline"
    case .sleeping: "Sleeping"
    case .needsAttention(let reason): reason
    }
  }

  /// The state calls for a visit to Settings.
  public var needsSettings: Bool {
    switch self {
    case .notConfigured, .needsAttention: true
    case .connecting, .connected, .retrying, .offline, .sleeping: false
    }
  }

  /// Messages cannot arrive right now.
  public var isDisconnected: Bool {
    switch self {
    case .retrying, .offline, .needsAttention: true
    case .notConfigured, .connecting, .connected, .sleeping: false
    }
  }

  static func reason(for error: NtfyError) -> String {
    switch error {
    case .unauthorized: "The server rejected the access token"
    case .redirected: "The server address redirects; check the URL"
    case .insecureServer: "A token needs an https server"
    case .invalidTopic: "A topic name is not accepted by the server"
    case .permissionDenied: "Permission denied"
    case .serverUnreachable, .rateLimited, .appUnavailable, .invalidResponse, .storage:
      "The connection stopped"
    }
  }
}
