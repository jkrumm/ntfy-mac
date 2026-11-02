import Synchronization

/// Fans the current status out to any number of `AsyncStream` subscribers; each one starts with
/// the status at subscription time and then sees every change.
final class StatusBroadcaster: Sendable {
  private struct State {
    var current = ConnectionStatus.stopped
    var nextID = 0
    var subscribers: [Int: AsyncStream<ConnectionStatus>.Continuation] = [:]
  }

  private let state = Mutex(State())

  var current: ConnectionStatus { state.withLock { $0.current } }

  func stream() -> AsyncStream<ConnectionStatus> {
    AsyncStream(ConnectionStatus.self, bufferingPolicy: .unbounded) { continuation in
      let id = state.withLock { state -> Int in
        defer { state.nextID += 1 }
        state.subscribers[state.nextID] = continuation
        continuation.yield(state.current)
        return state.nextID
      }
      continuation.onTermination = { [weak self] _ in
        self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
      }
    }
  }

  func publish(_ status: ConnectionStatus) {
    let subscribers = state.withLock { state -> [AsyncStream<ConnectionStatus>.Continuation] in
      guard state.current != status else { return [] }
      state.current = status
      return Array(state.subscribers.values)
    }
    for subscriber in subscribers { subscriber.yield(status) }
  }
}
