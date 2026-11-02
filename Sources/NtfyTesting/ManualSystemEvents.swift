import NtfyCore
import Synchronization

/// System events that only happen when the test sends them. Reaches every current subscriber.
public final class ManualSystemEvents: SystemEvents {
  private struct State {
    var nextID = 0
    var subscribers: [Int: AsyncStream<SystemEvent>.Continuation] = [:]
  }

  private let state = Mutex(State())

  public init() {}

  public func events() -> AsyncStream<SystemEvent> {
    AsyncStream(SystemEvent.self, bufferingPolicy: .unbounded) { continuation in
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

  public func send(_ event: SystemEvent) {
    let current = state.withLock { Array($0.subscribers.values) }
    for continuation in current { continuation.yield(event) }
  }
}
