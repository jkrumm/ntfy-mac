import Foundation

/// What ArgumentParser cannot say about a command: what it depends on, which stable error codes
/// it can end with, and the type and range of its values. One entry per top-level command;
/// subcommands share their parent's. `SchemaTests` fails when a command and its spec disagree.
struct CommandSpec: Sendable {
  enum AppUse: String, Sendable {
    /// Never talks to the app.
    case none
    /// Asks the app when it runs, never starts it.
    case optional
    /// Starts the app when it is down.
    case launches
  }

  /// The type and allowed values of one argument, by its name (`--limit`, or `topic` for a
  /// positional). Arguments without an entry are plain strings (flags: booleans).
  struct Domain: Sendable {
    var type: String
    var range: ClosedRange<Int>?
    var unit: String?

    static let string = Domain(type: "string")
    static let url = Domain(type: "url")
    static let seconds = Domain(type: "number", unit: "seconds")
    static let duration = Domain(type: "duration")
    static let timestamp = Domain(type: "timestamp")
    static let durationOrTimestamp = Domain(type: "duration-or-timestamp")
    static let priority = Domain(type: "integer", range: 1...5)
    static let limit = Domain(type: "integer", range: 1...HistoryFilterOptions.maxLimit)

    init(type: String, range: ClosedRange<Int>? = nil, unit: String? = nil) {
      self.type = type
      self.range = range
      self.unit = unit
    }
  }

  let name: String
  let app: AppUse
  let server: Bool
  let files: Bool
  /// Why `app` is what it is, when it depends on a flag.
  let note: String?
  /// Error codes this command can end with, beyond `usage`.
  let errors: [String]
  let domains: [String: Domain]

  init(
    _ name: String, app: AppUse = .none, server: Bool = false, files: Bool = false,
    note: String? = nil, errors: [String] = [], domains: [String: Domain] = [:]
  ) {
    self.name = name
    self.app = app
    self.server = server
    self.files = files
    self.note = note
    self.errors = errors
    self.domains = domains
  }
}

extension CommandSpec {
  private static let history = ["storage"]
  private static let appErrors = ["app-unavailable", "permission-denied", "not-found", "internal"]
  private static let serverErrors = [
    "not-configured", "config-invalid", "unauthorized", "server-unreachable", "rate-limited",
    "redirected", "insecure-server", "invalid-response",
  ]
  private static let filters: [String: Domain] = [
    "--limit": .limit, "--min-priority": .priority, "--since": .durationOrTimestamp,
  ]

  /// Every registered top-level command has exactly one entry.
  static let all: [CommandSpec] = [
    CommandSpec(
      "setup", server: true, files: true, errors: serverErrors + ["setup-cancelled"],
      domains: ["--url": .url]),
    CommandSpec("doctor", app: .optional, server: true, files: true, errors: serverErrors),
    CommandSpec("subscribe", server: true, files: true, errors: serverErrors),
    CommandSpec("unsubscribe", files: true, errors: ["topic-not-local"]),
    CommandSpec("config", files: true, domains: ["priority": .priority]),
    CommandSpec(
      "notify", app: .launches, errors: ["app-unavailable", "permission-denied"],
      domains: ["--priority": .priority, "--dismiss-after": .seconds, "--url": .url]),
    CommandSpec("sounds", files: true, errors: ["no-match"]),
    CommandSpec("logs", errors: ["logs-failed"], domains: ["--last": .duration]),
    CommandSpec(
      "update", errors: ["update-unsupported", "update-failed", "server-unreachable"]),
    CommandSpec("uninstall", app: .optional, files: true, errors: ["cancelled"]),
    CommandSpec("version"),
    CommandSpec("start", app: .launches, errors: ["app-unavailable"]),
    CommandSpec("status", app: .optional, files: true, errors: history),
    CommandSpec("ls", files: true, errors: history, domains: filters),
    CommandSpec("search", files: true, errors: history, domains: filters),
    CommandSpec("read", files: true, errors: ["not-found"] + history),
    CommandSpec("ack", app: .launches, errors: appErrors),
    CommandSpec("tail", files: true, errors: history, domains: filters),
    CommandSpec(
      "wait", app: .launches, files: true, note: "Starts the app only with --ack.",
      errors: ["timeout"] + appErrors + history,
      domains: ["--timeout": .seconds, "--min-priority": .priority]),
    CommandSpec(
      "publish", server: true, files: true,
      errors: serverErrors + ["invalid-topic"],
      domains: ["--priority": .priority, "--click": .url]),
    CommandSpec(
      "pause", files: true, errors: ["storage"],
      domains: ["--for": .duration, "--until": .timestamp]),
    CommandSpec("resume", files: true, errors: ["storage"]),
    CommandSpec("login-item", app: .launches, errors: ["app-unavailable", "internal"]),
    CommandSpec("schema"),
  ]

  static func named(_ name: String) -> CommandSpec? { all.first { $0.name == name } }
}

/// The stable process exit codes and the error codes behind them.
enum ErrorCatalog {
  struct Entry: Encodable, Sendable {
    let code: String
    let exitCode: Int32
    let meaning: String
  }

  static let exitMeanings: [ProcessExit: String] = [
    .success: "The command did what it was asked.",
    .runtime: "A runtime failure; the error code says which (see errorCodes).",
    .usage: "Invalid flags, arguments or values; nothing was done.",
    .auth: "The server rejected the token.",
    .appUnavailable: "The app is not running, or a system permission it needs is missing.",
    .serverUnreachable: "The ntfy server could not be reached.",
  ]

  static let errors: [Entry] = [
    Entry(code: "usage", exitCode: 2, meaning: "Invalid flags, arguments or values."),
    Entry(code: "not-configured", exitCode: 1, meaning: "No server URL or token yet; run setup."),
    Entry(code: "config-invalid", exitCode: 1, meaning: "The configured URL or token is unusable."),
    Entry(code: "not-found", exitCode: 1, meaning: "No such message in the history."),
    Entry(code: "timeout", exitCode: 1, meaning: "wait found no matching message in time."),
    Entry(code: "unauthorized", exitCode: 3, meaning: "The server rejected the token (401/403)."),
    Entry(code: "server-unreachable", exitCode: 7, meaning: "The server did not answer."),
    Entry(code: "rate-limited", exitCode: 1, meaning: "The server answered 429; retry later."),
    Entry(code: "redirected", exitCode: 1, meaning: "The server redirected; the URL is wrong."),
    Entry(code: "insecure-server", exitCode: 1, meaning: "A token over plain http is refused."),
    Entry(code: "invalid-topic", exitCode: 2, meaning: "A topic name the server would not accept."),
    Entry(
      code: "app-unavailable", exitCode: 4, meaning: "The app is not running or not reachable."),
    Entry(code: "permission-denied", exitCode: 4, meaning: "Notifications are not allowed."),
    Entry(code: "invalid-response", exitCode: 1, meaning: "An answer that could not be read."),
    Entry(code: "storage", exitCode: 1, meaning: "Reading or writing local state failed."),
    Entry(code: "internal", exitCode: 1, meaning: "The app failed while handling the request."),
    Entry(code: "topic-not-local", exitCode: 1, meaning: "Only local topics can be removed."),
    Entry(code: "no-match", exitCode: 1, meaning: "No sound matches the filter."),
    Entry(code: "cancelled", exitCode: 1, meaning: "The user declined the confirmation."),
    Entry(code: "setup-cancelled", exitCode: 1, meaning: "The setup wizard was cancelled."),
    Entry(code: "logs-failed", exitCode: 1, meaning: "The log tool failed."),
    Entry(code: "update-unsupported", exitCode: 1, meaning: "This install cannot update itself."),
    Entry(code: "update-failed", exitCode: 1, meaning: "The upgrade command failed."),
    Entry(code: "error", exitCode: 1, meaning: "Any other failure."),
  ]
}
