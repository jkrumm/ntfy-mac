import Foundation
import NtfyCore
import NtfyStore
import NtfyTesting
import Testing

/// A throwaway directory under the system temp dir; tests never touch the real home.
final class TempDirectory: Sendable {
  let url: URL

  init() {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-store-tests-\(UUID().uuidString)", isDirectory: true)
  }

  deinit { try? FileManager.default.removeItem(at: url) }

  var databaseURL: URL {
    url.appendingPathComponent("data").appendingPathComponent("history.sqlite")
  }

  func permissions(_ path: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    return (attributes[.posixPermissions] as? Int) ?? -1
  }
}

typealias AnyHistory = HistoryStore & HistoryInbox

/// The two implementations of the shared history contract.
enum Backend: String, CaseIterable, Sendable, CustomTestStringConvertible {
  case sqlite
  case memory

  var testDescription: String { rawValue }
}

/// A store under test with the clock it reads and the directory that holds it.
struct HistoryRig {
  static let server = "https://ntfy.example.com"

  let store: any AnyHistory
  let clock: FakeClock
  let directory = TempDirectory()

  init(_ backend: Backend) throws {
    clock = FakeClock()
    switch backend {
    case .memory:
      store = InMemoryHistoryStore(clock: clock)
    case .sqlite:
      store = try SQLiteHistoryStore.open(
        at: directory.databaseURL, server: Self.server, clock: clock)
    }
  }

  /// A message `offset` seconds after the clock's start.
  func message(
    _ id: String, topic: String = "alerts", at offset: TimeInterval = 0, title: String? = nil,
    body: String = "body", priority: Priority = .default, sequenceID: String? = nil
  ) -> NtfyMessage {
    NtfyMessage(
      id: id, topic: topic, time: clock.now().addingTimeInterval(offset), title: title,
      body: body, priority: priority, sequenceID: sequenceID)
  }
}
