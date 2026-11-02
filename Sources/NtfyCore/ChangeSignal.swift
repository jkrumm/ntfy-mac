import Synchronization

/// Fans a bare "something changed" out to any number of `AsyncStream` subscribers. Each
/// subscriber buffers at most one pending signal, so a burst of `fire()` calls reaches a slow
/// consumer as one element.
public final class ChangeSignal: Sendable {
  private struct State {
    var nextID = 0
    var subscribers: [Int: AsyncStream<Void>.Continuation] = [:]
  }

  private let state = Mutex(State())

  public init() {}

  /// Elements from now on; the stream ends when the consumer stops iterating.
  public func stream() -> AsyncStream<Void> {
    AsyncStream(Void.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
      let id = state.withLock { state -> Int in
        defer { state.nextID += 1 }
        state.subscribers[state.nextID] = continuation
        return state.nextID
      }
      continuation.onTermination = { [weak self] _ in
        self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
      }
    }
  }

  public func fire() {
    let subscribers = state.withLock { Array($0.subscribers.values) }
    for subscriber in subscribers { subscriber.yield() }
  }
}
