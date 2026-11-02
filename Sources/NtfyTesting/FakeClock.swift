import Foundation
import NtfyCore
import Synchronization

/// A clock that only moves when the test says so. Sleepers wake once `advance` passes their deadline.
public final class FakeClock: NtfyCore.Clock {
  fileprivate struct Sleeper {
    let id: UUID
    let deadline: Date
    let continuation: CheckedContinuation<Void, any Error>
  }

  fileprivate struct State {
    var now: Date
    var sleepers: [Sleeper] = []
  }

  fileprivate let state: Mutex<State>

  public init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
    state = Mutex(State(now: start))
  }

  /// Number of tasks currently suspended in `sleep`.
  public var sleeperCount: Int { state.withLock { $0.sleepers.count } }

  public func now() -> Date { state.withLock { $0.now } }

  public func advance(by duration: Duration) {
    let due = state.withLock { state -> [Sleeper] in
      state.now = state.now.addingTimeInterval(duration.timeInterval)
      let due = state.sleepers.filter { $0.deadline <= state.now }
      state.sleepers.removeAll { $0.deadline <= state.now }
      return due
    }
    for sleeper in due.sorted(by: { $0.deadline < $1.deadline }) {
      sleeper.continuation.resume()
    }
  }

  public func sleep(for duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let outcome = register(id: id, duration: duration, continuation: continuation)
        if let outcome { continuation.resume(with: outcome) }
      }
    } onCancel: {
      let sleeper = state.withLock { state -> Sleeper? in
        guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
        return state.sleepers.remove(at: index)
      }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }
}

extension FakeClock {
  /// Parks the continuation, or returns the outcome to resume with right away.
  fileprivate func register(
    id: UUID, duration: Duration, continuation: CheckedContinuation<Void, any Error>
  ) -> Result<Void, any Error>? {
    state.withLock { state in
      if Task.isCancelled { return .failure(CancellationError()) }
      let deadline = state.now.addingTimeInterval(duration.timeInterval)
      if deadline <= state.now { return .success(()) }
      state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
      return nil
    }
  }
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    let parts = components
    return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
  }
}
