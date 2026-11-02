import NtfyCore
import Synchronization

/// A signal source that reads what the test set and reports a change only when told to.
public final class ScriptedMeetingSignalSource: MeetingSignalSource {
  private let reading: Mutex<MeetingSnapshot>
  private let signal = ChangeSignal()
  private let reads = Mutex(0)

  public init(_ snapshot: MeetingSnapshot = MeetingSnapshot()) {
    reading = Mutex(snapshot)
  }

  /// How many snapshots were taken.
  public var snapshotCount: Int { reads.withLock { $0 } }

  /// Replaces the reading without reporting a change (a poll finds it).
  public func set(_ snapshot: MeetingSnapshot) {
    reading.withLock { $0 = snapshot }
  }

  /// Replaces the reading and reports a change, as a CoreAudio property listener does.
  public func update(_ snapshot: MeetingSnapshot) {
    set(snapshot)
    signal.fire()
  }

  public func snapshot() async -> MeetingSnapshot {
    reads.withLock { $0 += 1 }
    return reading.withLock { $0 }
  }

  public func changes() -> AsyncStream<Void> { signal.stream() }
}

/// A meeting state that only changes when the test says so.
public final class ManualMeetingState: MeetingStateProviding {
  private struct State {
    var current = MeetingState.inactive
    var nextID = 0
    var subscribers: [Int: AsyncStream<MeetingState>.Continuation] = [:]
  }

  private let state: Mutex<State>

  public init(_ initial: MeetingState = .inactive) {
    state = Mutex(State(current: initial))
  }

  public func current() async -> MeetingState { state.withLock { $0.current } }

  public func changes() -> AsyncStream<MeetingState> {
    AsyncStream(MeetingState.self, bufferingPolicy: .unbounded) { continuation in
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

  public func set(_ next: MeetingState) {
    let subscribers = state.withLock { state -> [AsyncStream<MeetingState>.Continuation] in
      state.current = next
      return Array(state.subscribers.values)
    }
    for subscriber in subscribers { subscriber.yield(next) }
  }
}
