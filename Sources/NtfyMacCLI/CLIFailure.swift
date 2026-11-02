import Foundation
import NtfyCore

/// A failure the CLI itself raises, with the stable code scripts can match on and the exit code.
struct CLIFailure: Error, Sendable, Hashable {
  let code: String
  let message: String
  let exit: ProcessExit

  static func usage(_ message: String) -> CLIFailure {
    CLIFailure(code: "usage", message: message, exit: .usage)
  }

  static func runtime(_ code: String, _ message: String) -> CLIFailure {
    CLIFailure(code: code, message: message, exit: .runtime)
  }

  static let notConfigured = CLIFailure.runtime(
    "not-configured", "Not configured. Run: ntfy-mac setup")
}

/// Ends the command with `exit` without printing anything: the command already reported
/// (a `doctor` report with failing checks).
struct ExitRequest: Error, Sendable {
  let exit: ProcessExit
}

/// What `--json` prints on stdout when a command fails, and what the human line is built from.
struct ErrorReport: Codable, Sendable, Hashable {
  let code: String
  let message: String
  let exitCode: Int32

  init(code: String, message: String, exit: ProcessExit) {
    self.code = code
    self.message = message
    exitCode = exit.rawValue
  }

  init(_ error: any Error) {
    let exit = ProcessExit(error: error)
    switch error {
    case let failure as CLIFailure:
      self.init(code: failure.code, message: failure.message, exit: exit)
    case let error as NtfyError:
      self.init(code: error.code, message: error.cliMessage, exit: exit)
    default:
      self.init(code: exit == .usage ? "usage" : "error", message: "\(error)", exit: exit)
    }
  }
}

struct ErrorEnvelope: Encodable, Sendable {
  let error: ErrorReport
}

extension NtfyError {
  /// Stable kebab-case identifier for `--json` consumers.
  var code: String {
    switch self {
    case .unauthorized: "unauthorized"
    case .serverUnreachable: "server-unreachable"
    case .rateLimited: "rate-limited"
    case .redirected: "redirected"
    case .insecureServer: "insecure-server"
    case .invalidTopic: "invalid-topic"
    case .appUnavailable: "app-unavailable"
    case .permissionDenied: "permission-denied"
    case .invalidResponse: "invalid-response"
    case .storage: "storage"
    }
  }

  var cliMessage: String {
    switch self {
    case .unauthorized: "The server rejected the token. Run: ntfy-mac setup"
    case .serverUnreachable: "Cannot reach the ntfy server."
    case .rateLimited(let retryAfter):
      "The server is rate limiting requests" + (retryAfter.map { " (retry in \($0)s)" } ?? "")
    case .redirected: "The server redirected the request; check the server URL (ntfy-mac setup)."
    case .insecureServer: "Refusing to send the token over plain http; use an https server URL."
    case .invalidTopic(let name): "Invalid topic name: \(name)"
    case .appUnavailable: "The ntfy-mac app is not running. Start it with: ntfy-mac start"
    case .permissionDenied: "A system permission is missing. Run: ntfy-mac doctor"
    case .invalidResponse(let detail): "Unexpected response: \(detail)"
    case .storage(let detail): detail
    }
  }
}
