import NtfyCore
import Synchronization

/// A stream whose events the test pushes by hand, one connection per `events` call. `send`,
/// `finish` and `fail` act on the newest connection.
public final class ManualMessageStream: MessageStream {
  public struct Call: Sendable, Hashable {
    public let topics: [String]
    public let since: String?
  }

  private typealias Continuation = AsyncThrowingStream<StreamEvent, any Error>.Continuation

  private struct State {
    var calls: [Call] = []
    var connections: [Continuation] = []
    var live: Set<Int> = []
  }

  private let state = Mutex(State())

  public init() {}

  /// Every `events(topics:since:)` call so far, oldest first.
  public var calls: [Call] { state.withLock { $0.calls } }

  /// Connections whose consumer has not cancelled them and that were not finished.
  public var liveConnectionCount: Int { state.withLock { $0.live.count } }

  public func events(
    topics: [String], since: String?
  ) -> AsyncThrowingStream<StreamEvent, any Error> {
    AsyncThrowingStream(StreamEvent.self, bufferingPolicy: .unbounded) { continuation in
      let index = state.withLock { state -> Int in
        state.calls.append(Call(topics: topics, since: since))
        state.connections.append(continuation)
        state.live.insert(state.calls.count - 1)
        return state.calls.count - 1
      }
      continuation.onTermination = { [weak self] _ in
        self?.state.withLock { _ = $0.live.remove(index) }
      }
    }
  }

  public func send(_ event: StreamEvent) {
    newest?.yield(event)
  }

  public func send(_ message: NtfyMessage) {
    send(.message(message))
  }

  /// Ends the newest connection as the server closing it cleanly.
  public func finish() {
    newest?.finish()
  }

  /// Ends the newest connection with an error.
  public func fail(_ error: NtfyError) {
    newest?.finish(throwing: error)
  }

  private var newest: Continuation? { state.withLock { $0.connections.last } }
}
