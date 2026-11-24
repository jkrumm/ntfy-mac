import ArgumentParser
import Foundation
import NtfyCore

/// What `summary` prints.
struct SummaryReport: Encodable, Sendable {
  let since: Date
  let count: Int
  /// `model`, `deterministic`, or `none` when there was nothing to summarize.
  let source: String
  let summary: String
  /// Why the model's text is missing although the digest is configured.
  let failure: String?

  var text: String {
    guard count > 0 else { return summary }
    var lines = ["While you were away · \(count) \(count == 1 ? "message" : "messages")", summary]
    if let failure { lines.append("(model unavailable: \(failure))") }
    return lines.joined(separator: "\n")
  }
}

struct SummaryTestReport: Encodable, Sendable {
  let ok: Bool  // swiftlint:disable:this identifier_name
  let model: String
  let reply: String
}

/// The same digest the app posts when you return, printed instead of posted.
struct SummaryCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "summary",
    abstract: "Summarize the notifications of a time window, as the away digest does.",
    discussion: """
      Reads the history read-only and prints the digest of the messages that were shown as
      notifications since --since (default 1h). With the digest on, an endpoint and a key (see
      config summary-key) the model writes it; otherwise, or when the endpoint fails, it is the
      counts per topic. Nothing is posted. NTFY_SUMMARY_KEY replaces the stored key for this run.
      --test sends one tiny request to the endpoint and prints the model's answer.

        ntfy-mac summary --since 1h
        ntfy-mac summary --test
      """)

  @Option(name: .long, help: "Start of the window: a duration such as 2h, or an ISO 8601 time.")
  var since = "1h"
  @Flag(name: .long, help: "Send one tiny request to the endpoint instead of summarizing.")
  var test = false
  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard TimePoint.parse(since, now: Date()) != nil else {
      throw ValidationError("--since must be a duration such as 2h, or an ISO 8601 time.")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let config = try await environment.config.load()
    if test {
      try await runTest(config, environment, out)
      return
    }
    let now = environment.clock.now()
    guard let start = TimePoint.parse(since, now: now) else { return }
    guard let inbox = try await environment.openHistory() else {
      return report(
        SummaryReport(since: start, count: 0, source: "none", summary: empty, failure: nil), out)
    }
    let builder = DigestBuilder(inbox: inbox)
    let messages = try await builder.collect(since: start, config: config)
    guard !messages.isEmpty else {
      return report(
        SummaryReport(since: start, count: 0, source: "none", summary: empty, failure: nil), out)
    }
    let summarizer = await environment.summarizers.summarizer(for: config)
    let digest = await builder.digest(of: messages, config: config, summarizer: summarizer)
    report(
      SummaryReport(
        since: start, count: digest.count, source: digest.usedModel ? "model" : "deterministic",
        summary: digest.text, failure: digest.failure), out)
  }

  private var empty: String { "No notified messages since \(since)." }

  private func report(_ report: SummaryReport, _ out: Output) {
    out.result(report, text: report.text)
  }

  private func runTest(
    _ config: Config, _ environment: CLIEnvironment, _ out: Output
  ) async throws {
    guard let endpoint = config.summary.endpoint else {
      throw CLIFailure.runtime(
        "summary-not-configured",
        "No endpoint. Set one: ntfy-mac config set summary.endpoint https://api.anthropic.com")
    }
    guard
      let summarizer = await environment.summarizers.summarizer(
        endpoint: endpoint, model: config.summary.model, allowInsecure: config.allowInsecure)
    else {
      throw CLIFailure.runtime(
        "summary-not-configured",
        "No usable key or endpoint. Store the key: ntfy-mac config summary-key set")
    }
    let sample = DigestEntry(
      topic: "test", priority: 3, time: environment.clock.now(), title: "Test",
      body: "ntfy-mac checks that the summary endpoint answers.")
    let reply = try await summarizer.summarize([sample])
    let report = SummaryTestReport(ok: true, model: config.summary.model, reply: reply)
    out.result(report, text: "OK (\(report.model)): \(reply)")
  }
}

struct ConfigSummaryKeyCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "summary-key", abstract: "Store or remove the API key of the summary endpoint.",
    discussion: """
      The key lives in the Keychain, never in config.json. `set` reads it from stdin so it stays
      out of the shell history and the process list.

        printf %s "$KEY" | ntfy-mac config summary-key set
        ntfy-mac config summary-key clear
      """,
    subcommands: [SummaryKeySet.self, SummaryKeyClear.self])

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let stored = try await environment.summaryKeys.token() != nil
    out.result(
      SummaryKeyReport(stored: stored), text: stored ? "A key is stored." : "No key stored.")
  }
}

struct SummaryKeyReport: Encodable, Sendable {
  let stored: Bool
}

struct SummaryKeySet: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "set", abstract: "Store the key read from stdin.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    guard !environment.terminal.stdinIsTTY else {
      throw CLIFailure.usage(
        "The key is read from stdin: printf %s \"$KEY\" | ntfy-mac config summary-key set")
    }
    let key =
      String(bytes: environment.readStandardInput(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !key.isEmpty else { throw CLIFailure.usage("No key on stdin.") }
    try await environment.summaryKeys.setToken(key)
    out.result(SummaryKeyReport(stored: true), text: "Key stored in the Keychain.")
  }
}

struct SummaryKeyClear: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "clear", abstract: "Remove the stored key.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await environment.summaryKeys.deleteToken()
    out.result(SummaryKeyReport(stored: false), text: "Key removed.")
  }
}

/// The Keychain key, unless `NTFY_SUMMARY_KEY` is set: for a host without a usable Keychain and
/// for one-off runs. Writes always go to the Keychain.
struct EnvironmentSecretStore: SecretStore {
  let override: String?
  let base: any SecretStore

  func token() async throws(NtfyError) -> String? {
    if let override, !override.isEmpty { return override }
    return try await base.token()
  }

  func setToken(_ token: String) async throws(NtfyError) { try await base.setToken(token) }
  func deleteToken() async throws(NtfyError) { try await base.deleteToken() }
}

extension CLIEnvironment {
  var summarizers: SummarizerProvider {
    SummarizerProvider(keys: summaryKeys, make: summarizerMake)
  }
}
