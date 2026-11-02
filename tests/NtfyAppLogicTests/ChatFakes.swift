import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting

/// Publishes into the in-memory history, the way the server's echo does over the stream.
actor RecordingPublisher: NtfyPublishing {
  private let history: InMemoryHistoryStore
  private let clock: FakeClock
  private(set) var requests: [PublishRequest] = []
  private var failure: NtfyError?
  private var gate: CheckedContinuation<Void, Never>?
  private var held = false
  private var counter = 0

  init(history: InMemoryHistoryStore, clock: FakeClock) {
    self.history = history
    self.clock = clock
  }

  func fail(with error: NtfyError?) { failure = error }

  /// The next publish waits until `release()`.
  func hold() { held = true }

  func release() {
    held = false
    gate?.resume()
    gate = nil
  }

  func publish(_ request: PublishRequest) async throws(NtfyError) -> PublishedMessage {
    requests.append(request)
    if held { await withCheckedContinuation { gate = $0 } }
    if let failure { throw failure }
    counter += 1
    let id = "sent-\(counter)"
    let now = clock.now()
    _ = try? await history.append(
      NtfyMessage(
        id: id, topic: request.topic, time: now, title: request.title, body: request.message,
        priority: request.priority ?? .default))
    return PublishedMessage(id: id, topic: request.topic, time: now)
  }
}

struct StubPublisherProvider: PublisherProviding {
  let resolution: PublisherResolution

  func resolve() async throws(NtfyError) -> PublisherResolution { resolution }
}

struct FailingPublisherProvider: PublisherProviding {
  let error: NtfyError

  func resolve() async throws(NtfyError) -> PublisherResolution { throw error }
}
