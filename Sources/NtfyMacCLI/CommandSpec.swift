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
    static let time = Domain(type: "time", unit: "HH:mm")
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
  /// Complete command lines, as an agent would type them. At least one per command.
  let examples: [String]

  init(
    _ name: String, app: AppUse = .none, server: Bool = false, files: Bool = false,
    note: String? = nil, errors: [String] = [], domains: [String: Domain] = [:],
    examples: [String]
  ) {
    self.name = name
    self.app = app
    self.server = server
    self.files = files
    self.note = note
    self.errors = errors
    self.domains = domains
    self.examples = examples
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
      domains: ["--url": .url],
      examples: ["ntfy-mac setup", "ntfy-mac setup --url https://ntfy.example.com --token tk_..."]),
    CommandSpec(
      "doctor", app: .optional, server: true, files: true, errors: serverErrors,
      examples: ["ntfy-mac doctor", "ntfy-mac doctor --json", "ntfy-mac doctor --send-test"]),
    CommandSpec(
      "subscribe", server: true, files: true, errors: serverErrors,
      examples: ["ntfy-mac subscribe", "ntfy-mac subscribe builds", "ntfy-mac subscribe reset"]),
    CommandSpec(
      "unsubscribe", files: true, errors: ["topic-not-local"],
      examples: ["ntfy-mac unsubscribe builds"]),
    CommandSpec(
      "config", files: true,
      domains: [
        "priority": .priority, "--min-priority": .priority, "--start": .time, "--end": .time,
      ],
      examples: [
        "ntfy-mac config", "ntfy-mac config show --json", "ntfy-mac config sounds list",
        "ntfy-mac config sounds set 5 Sosumi", "ntfy-mac config dismiss set 3 15",
        "ntfy-mac config dismiss set 5 never", "ntfy-mac config sounds reset",
        "ntfy-mac config get reAlert", "ntfy-mac config set reAlertIntervalSeconds 600",
        "ntfy-mac config reset reAlertIntervalSeconds", "ntfy-mac config topic list",
        "ntfy-mac config topic set builds --mute --min-priority 4 --emoji 🔨",
        "ntfy-mac config topic show builds", "ntfy-mac config topic reset builds",
        "ntfy-mac config quiet-hours show",
        "ntfy-mac config quiet-hours set --start 22:00 --end 07:00 --no-digest",
        "ntfy-mac config quiet-hours off", "ntfy-mac config meeting show",
        "ntfy-mac config meeting set --mode pause --no-urgent-bypass",
        "ntfy-mac config meeting reset",
      ]),
    CommandSpec(
      "notify", app: .launches, errors: ["app-unavailable", "permission-denied"],
      domains: ["--priority": .priority, "--dismiss-after": .seconds, "--url": .url],
      examples: [
        "ntfy-mac notify -m \"Deploy complete\"",
        "ntfy-mac notify -t Alert -m \"Disk usage above 90%\" -p 5",
        "echo '{\"title\":\"T\",\"body\":\"B\"}' | ntfy-mac notify --json",
      ]),
    CommandSpec(
      "sounds", files: true, errors: ["no-match"],
      examples: ["ntfy-mac sounds", "ntfy-mac sounds glass"]),
    CommandSpec(
      "logs", errors: ["logs-failed"], domains: ["--last": .duration],
      examples: ["ntfy-mac logs --last 1h", "ntfy-mac logs --error --follow"]),
    CommandSpec(
      "update",
      errors: [
        "update-unsupported", "update-disabled", "update-not-writable", "update-invalid",
        "checksum-mismatch", "update-failed", "server-unreachable",
      ],
      examples: ["ntfy-mac update --check", "ntfy-mac update"]),
    CommandSpec(
      "uninstall", app: .optional, files: true, errors: ["cancelled"],
      examples: ["ntfy-mac uninstall --yes"]),
    CommandSpec(
      "migrate", files: true,
      examples: ["ntfy-mac migrate --dry-run", "ntfy-mac migrate", "ntfy-mac migrate --json"]),
    CommandSpec("version", examples: ["ntfy-mac version", "ntfy-mac version --json"]),
    CommandSpec(
      "start", app: .launches, errors: ["app-unavailable"], examples: ["ntfy-mac start"]),
    CommandSpec(
      "status", app: .optional, files: true, errors: history,
      examples: ["ntfy-mac status --json", "ntfy-mac status --require-running"]),
    CommandSpec(
      "ls", files: true, errors: history, domains: filters,
      examples: [
        "ntfy-mac ls --json --topic alerts --unread --limit 5",
        "ntfy-mac ls --unacked --min-priority 4 --since 2h",
      ]),
    CommandSpec(
      "search", files: true, errors: history, domains: filters,
      examples: ["ntfy-mac search disk --json", "ntfy-mac search deploy --topic builds --since 1d"]),
    CommandSpec(
      "read", files: true, errors: ["not-found"] + history,
      examples: ["ntfy-mac read alerts m1 --json", "ntfy-mac read alerts m1 --no-mark"]),
    CommandSpec(
      "ack", app: .launches, errors: appErrors,
      examples: ["ntfy-mac ack alerts m1", "ntfy-mac ack --all --topic alerts"]),
    CommandSpec(
      "remind", app: .launches, errors: appErrors,
      domains: ["--in": .duration, "--until": .timestamp],
      examples: [
        "ntfy-mac remind alerts m1 --in 1h",
        "ntfy-mac remind alerts m1 --until 2030-01-01T08:00:00Z",
      ]),
    CommandSpec(
      "delete", app: .launches, errors: appErrors + ["app-outdated"],
      examples: ["ntfy-mac delete alerts m1", "ntfy-mac delete --topic alerts --all"]),
    CommandSpec(
      "tail", files: true, errors: history, domains: filters,
      examples: [
        "ntfy-mac tail --topic alerts --since 1h --limit 10",
        "ntfy-mac tail --topic alerts --follow",
      ]),
    CommandSpec(
      "wait", app: .launches, files: true, note: "Starts the app only with --ack.",
      errors: ["timeout"] + appErrors + history,
      domains: ["--timeout": .seconds, "--min-priority": .priority],
      examples: [
        "ntfy-mac wait --topic alerts --match approve --timeout 600 --json",
        "ntfy-mac wait --topic alerts --match '/^approve/i' --ack",
      ]),
    CommandSpec(
      "publish", server: true, files: true,
      errors: serverErrors + ["invalid-topic"],
      domains: ["--priority": .priority, "--click": .url],
      examples: [
        "ntfy-mac publish builds -m \"Deploy complete\" -t CI -p 4",
        "echo \"build done\" | ntfy-mac publish builds -m - --tag white_check_mark",
      ]),
    CommandSpec(
      "pause", files: true, errors: ["storage"],
      domains: ["--for": .duration, "--until": .timestamp],
      examples: [
        "ntfy-mac pause --for 30m", "ntfy-mac pause --until 2030-01-01T08:00:00Z", "ntfy-mac pause",
      ]),
    CommandSpec("resume", files: true, errors: ["storage"], examples: ["ntfy-mac resume"]),
    CommandSpec(
      "present", files: true, errors: ["storage"], domains: ["--for": .duration],
      examples: [
        "ntfy-mac present on", "ntfy-mac present on --for 2h", "ntfy-mac present on --indefinitely",
        "ntfy-mac present off",
      ]),
    CommandSpec(
      "login-item", app: .launches, errors: ["app-unavailable", "internal"],
      examples: ["ntfy-mac login-item status", "ntfy-mac login-item on"]),
    CommandSpec("schema", examples: ["ntfy-mac schema --json"]),
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
    Entry(
      code: "app-outdated", exitCode: 1,
      meaning: "The running app is older than the CLI and does not know the command."),
    Entry(code: "storage", exitCode: 1, meaning: "Reading or writing local state failed."),
    Entry(code: "internal", exitCode: 1, meaning: "The app failed while handling the request."),
    Entry(code: "topic-not-local", exitCode: 1, meaning: "Only local topics can be removed."),
    Entry(code: "no-match", exitCode: 1, meaning: "No sound matches the filter."),
    Entry(code: "cancelled", exitCode: 1, meaning: "The user declined the confirmation."),
    Entry(code: "setup-cancelled", exitCode: 1, meaning: "The setup wizard was cancelled."),
    Entry(code: "logs-failed", exitCode: 1, meaning: "The log tool failed."),
    Entry(code: "update-unsupported", exitCode: 1, meaning: "This install cannot update itself."),
    Entry(
      code: "update-disabled", exitCode: 1,
      meaning: "Self-update is turned off by NTFY_MAC_NO_SELF_UPDATE=1."),
    Entry(
      code: "update-not-writable", exitCode: 1,
      meaning: "The folder that holds NtfyMac.app is not writable."),
    Entry(
      code: "update-invalid", exitCode: 1,
      meaning: "The downloaded release failed verification; nothing was installed."),
    Entry(
      code: "checksum-mismatch", exitCode: 1,
      meaning: "The download does not match the release's SHA256SUMS; nothing was installed."),
    Entry(code: "update-failed", exitCode: 1, meaning: "The upgrade failed."),
    Entry(code: "error", exitCode: 1, meaning: "Any other failure."),
  ]
}
