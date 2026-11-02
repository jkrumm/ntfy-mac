import Foundation
import NtfyCore

/// Whether the standard streams are terminals. Prompts happen only when both are.
struct Terminal: Sendable, Hashable {
  var stdinIsTTY: Bool
  var stdoutIsTTY: Bool

  var isInteractive: Bool { stdinIsTTY && stdoutIsTTY }
}

/// Builds the account client for a server; the CLI's only way to reach a ntfy server.
typealias TopicSourceFactory =
  @Sendable (_ base: URL, _ token: String, _ allowInsecure: Bool) ->
  any TopicSource

/// Builds the publisher for a server.
typealias PublisherFactory =
  @Sendable (_ base: URL, _ token: String, _ allowInsecure: Bool) ->
  any NtfyPublishing

/// Runs `body` until it finishes or the process is interrupted (SIGINT, SIGTERM); an interrupt
/// ends it quietly instead of killing the process mid-write.
typealias InterruptibleRunner =
  @Sendable (_ body: @escaping @Sendable () async throws -> Void) async throws -> Void

/// Everything a command touches outside its own arguments. The one place real adapters are
/// chosen (`live`); tests build one from fakes.
struct CLIEnvironment: Sendable {
  var paths: CLIPaths
  /// The process environment (`NTFY_URL`, ...).
  var variables: [String: String]
  var terminal: Terminal
  var executablePath: String
  var config: any ConfigStore
  var secrets: any SecretStore
  var app: any AppControlling
  var topicSource: TopicSourceFactory
  var publisher: PublisherFactory
  var history: any HistoryOpening
  var clock: any NtfyCore.Clock
  var runUntilInterrupted: InterruptibleRunner
  var processes: any ProcessRunning
  var releases: any ReleaseLookup
  var legacy: LegacyInstallCleanup
  var prompter: any Prompting
  /// Reads all of stdin.
  var readStandardInput: @Sendable () -> Data
}

extension CLIEnvironment {
  /// The validated settings from file, Keychain and environment.
  /// - Throws: `CLIFailure.notConfigured` when there is no URL or token, a `config-invalid`
  ///   failure when one is unusable, or the store's `NtfyError`.
  func settings() async throws -> Settings {
    let stored = try await config.loadChecked()
    let token = try await secrets.token()
    do {
      switch try ConfigResolver.resolve(
        config: stored, keychainToken: token, environment: ConfigEnvironment(variables))
      {
      case .configured(let settings): return settings
      case .notConfigured: throw CLIFailure.notConfigured
      }
    } catch let error as ConfigError {
      throw CLIFailure.runtime("config-invalid", error.description)
    }
  }
}
