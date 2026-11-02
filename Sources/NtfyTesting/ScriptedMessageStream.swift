import NtfyCore
import Synchronization

/// Replays one script per connection, in order, and records the arguments of every call.
///
/// A script ends its connection by finishing (clean close), failing, or holding it open until
/// the consumer cancels. Calls beyond the scripted connections hold open too, so a reconnect
/// loop never spins in a test.
public final class ScriptedMessageStream: MessageStream {
  public enum Step: Sendable {
    case event(StreamEvent)
    case message(NtfyMessage)
    case fail(NtfyError)
    /// Keep the connection open without finishing.
    case hold
  }

  public struct Call: Sendable, Hashable {
    public let topics: [String]
    public let since: String?
  }

  private struct State {
    var scripts: [[Step]]
    var calls: [Call] = []
  }

  private let state: Mutex<State>

  /// A single connection.
  public convenience init(_ script: [Step]) {
    self.init(connections: [script])
  }

  public init(connections: [[Step]]) {
    state = Mutex(State(scripts: connections))
  }

  /// Every `events(topics:since:)` call so far, oldest first.
  public var calls: [Call] { state.withLock { $0.calls } }

  public func events(
    topics: [String], since: String?
  ) -> AsyncThrowingStream<StreamEvent, any Error> {
    let script = state.withLock { state -> [Step] in
      state.calls.append(Call(topics: topics, since: since))
      return state.scripts.isEmpty ? [.hold] : state.scripts.removeFirst()
    }
    return AsyncThrowingStream(StreamEvent.self, bufferingPolicy: .unbounded) { continuation in
      for step in script {
        switch step {
        case .event(let event):
          continuation.yield(event)
        case .message(let message):
          continuation.yield(.message(message))
        case .fail(let error):
          continuation.finish(throwing: error)
          return
        case .hold:
          return
        }
      }
      continuation.finish()
    }
  }
}
