import Foundation
import NtfyCore
import NtfyPlatform
import NtfyStore

/// Opens the history database for the CLI. Reads never need the app; the one write the CLI does
/// itself (marking a message read) goes through `writer`.
protocol HistoryOpening: Sendable {
  /// Read-only; nil when the app has not created a database yet (an empty history, not an error).
  func reader(server: String) throws(NtfyError) -> (any HistoryInbox)?
  /// Opens for writing. Call it only after `reader` succeeded, so the schema is known to be good.
  func writer(server: String) throws(NtfyError) -> any HistoryInbox
}

/// The SQLite file in the app's data directory. The writer is safe next to the running app: the
/// database is in WAL mode and `SQLiteHistoryStore.open` sets a 5 s busy timeout, so a one-row
/// `UPDATE` waits for the app's writes instead of failing.
struct SQLiteHistoryOpener: HistoryOpening {
  let database: URL

  func reader(server: String) throws(NtfyError) -> (any HistoryInbox)? {
    guard FileManager.default.fileExists(atPath: database.path) else { return nil }
    return try SQLiteHistoryStore.openReadOnly(
      at: database, server: server, clock: SystemClock())
  }

  func writer(server: String) throws(NtfyError) -> any HistoryInbox {
    try SQLiteHistoryStore.open(at: database, server: server, clock: SystemClock())
  }
}

extension CLIEnvironment {
  /// The key the history rows are stored under: the origin of the configured server (file, then
  /// `NTFY_URL`, as the app resolves it). Nil when no usable URL is configured.
  func historyServer() async throws(NtfyError) -> String? {
    let stored = try await config.load().url
    let raw = [stored, variables["NTFY_URL"]].compactMap { $0 }.first { !$0.isEmpty }
    guard let raw else { return nil }
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasSuffix("/") { text.removeLast() }
    guard let url = URL(string: text), url.scheme != nil, url.host() != nil else { return nil }
    return ServerOrigin.key(for: url)
  }

  /// The read-only history, nil when there is none yet.
  func openHistory() async throws(NtfyError) -> (any HistoryInbox)? {
    guard let server = try await historyServer() else { return nil }
    return try history.reader(server: server)
  }

  /// Opens the history on first use and again on every call until it exists, for commands that
  /// wait for the app to create it.
  func historyFeed() -> HistoryFeed {
    let environment = self
    return HistoryFeed { () async throws(NtfyError) -> (any HistoryInbox)? in
      try await environment.openHistory()
    }
  }
}

actor HistoryFeed {
  private let opener: @Sendable () async throws(NtfyError) -> (any HistoryInbox)?
  private var opened: (any HistoryInbox)?

  init(open: @escaping @Sendable () async throws(NtfyError) -> (any HistoryInbox)?) {
    self.opener = open
  }

  func inbox() async throws(NtfyError) -> (any HistoryInbox)? {
    if let opened { return opened }
    opened = try await opener()
    return opened
  }
}
