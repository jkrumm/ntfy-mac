import Foundation
import NtfyCore
import Synchronization

/// An ordered record of what the update ports were asked to do, shared between fakes.
public final class UpdateEventLog: Sendable {
  private let storage = Mutex<[String]>([])

  public init() {}

  public func append(_ event: String) { storage.withLock { $0.append(event) } }
  public var events: [String] { storage.withLock { $0 } }
}

/// Serves release assets from memory; a URL it does not know is unreachable.
public final class ScriptedAssetFetcher: ReleaseAssetFetching {
  private let assets: [URL: Data]
  private let failure: NtfyError?
  private let requested = Mutex<[URL]>([])

  public init(assets: [URL: Data], failure: NtfyError? = nil) {
    self.assets = assets
    self.failure = failure
  }

  public var requests: [URL] { requested.withLock { $0 } }

  public func download(_ url: URL, to file: URL, maxBytes: Int64) async throws(NtfyError) {
    requested.withLock { $0.append(url) }
    if let failure { throw failure }
    guard let data = assets[url] else { throw .serverUnreachable }
    guard Int64(data.count) <= maxBytes else { throw .invalidResponse("asset too large") }
    do {
      try data.write(to: file)
    } catch {
      throw .storage("cannot write \(file.lastPathComponent)")
    }
  }
}

/// A signature check that fails on the listed calls (1-based) and passes otherwise.
public final class ScriptedCodeSignature: CodeSignatureChecking {
  private let failingCalls: Set<Int>
  private let calls = Mutex(0)

  public init(failingCalls: Set<Int> = []) { self.failingCalls = failingCalls }

  public var callCount: Int { calls.withLock { $0 } }

  public func verify(_ bundle: URL) async throws(NtfyError) {
    let call = calls.withLock { value -> Int in
      value += 1
      return value
    }
    if failingCalls.contains(call) { throw .storage("signature rejected") }
  }
}

/// An app that is or is not running; records `stop` and `start` in the shared log.
public final class RecordingAppRestarter: AppRestarting {
  private let running: Bool
  private let stopFailure: NtfyError?
  private let log: UpdateEventLog

  public init(running: Bool, stopFailure: NtfyError? = nil, log: UpdateEventLog) {
    self.running = running
    self.stopFailure = stopFailure
    self.log = log
  }

  public func stopIfRunning(
    bundleIdentifier: String, timeout: Duration
  ) async throws(NtfyError) -> Bool {
    log.append("stop-if-running")
    if let stopFailure, running { throw stopFailure }
    return running
  }

  public func start(_ bundle: URL) async throws(NtfyError) {
    log.append("start")
  }
}
