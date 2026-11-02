import Foundation
import Synchronization

/// Watches a `MeetingSignalSource` and keeps the detected meeting state.
///
/// A reading is taken when the source says something changed (after `debounce`, so a burst of
/// property changes is one reading), when the policy's dwell or release deadline is due, and at
/// least every `pollInterval` as a backstop. All waiting runs on the injected `Clock`. While
/// stopped, nothing is read.
public actor MeetingMonitor: MeetingStateProviding {
  public static let pollInterval: Duration = .seconds(15)
  public static let debounce: Duration = .milliseconds(500)

  private let source: any MeetingSignalSource
  private let clock: any Clock
  private let poll: Duration
  private let debounce: Duration
  private let log: @Sendable (String) -> Void
  private let broadcaster = MeetingStateBroadcaster()
  private var policy: MeetingPolicy
  private var task: Task<Void, Never>?

  public init(
    source: any MeetingSignalSource, clock: any Clock, policy: MeetingPolicy = MeetingPolicy(),
    pollInterval: Duration = MeetingMonitor.pollInterval,
    debounce: Duration = MeetingMonitor.debounce,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.source = source
    self.clock = clock
    self.policy = policy
    poll = pollInterval
    self.debounce = debounce
    self.log = log
  }

  // MARK: MeetingStateProviding

  public func current() -> MeetingState { broadcaster.current }

  public nonisolated func changes() -> AsyncStream<MeetingState> { broadcaster.stream() }

  // MARK: Lifecycle

  /// Starts reading. Idempotent.
  public func start() {
    guard task == nil else { return }
    task = Task { await self.run() }
  }

  /// Stops reading and forgets the state: a meeting that was going on is over for the app.
  public func stop() async {
    guard let running = task else { return }
    task = nil
    running.cancel()
    await running.value
    policy = MeetingPolicy(dwell: policy.dwell, release: policy.release)
    broadcaster.publish(.inactive)
  }

  // MARK: Loop

  private func run() async {
    let (wakeups, wake) = AsyncStream.makeStream(
      of: Void.self, bufferingPolicy: .bufferingNewest(1))
    let changes = source.changes()
    let watcher = Task {
      for await _ in changes {
        do { try await clock.sleep(for: debounce) } catch { return }
        wake.yield()
      }
    }
    var timer: Task<Void, Never>?
    wake.yield()
    for await _ in wakeups {
      if Task.isCancelled { break }
      await evaluate()
      timer?.cancel()
      let wait = nextWait()
      timer = Task {
        do { try await clock.sleep(for: wait) } catch { return }
        wake.yield()
      }
    }
    watcher.cancel()
    timer?.cancel()
    wake.finish()
  }

  private func evaluate() async {
    let snapshot = await source.snapshot()
    guard !Task.isCancelled else { return }
    let before = policy.state
    let after = policy.evaluate(snapshot, at: clock.now())
    guard after != before else { return }
    log("meeting state: \(String(describing: after))")
    broadcaster.publish(after)
  }

  /// Until the policy's deadline if it is ahead, else the poll interval.
  private func nextWait() -> Duration {
    guard let deadline = policy.nextDeadline else { return poll }
    let seconds = deadline.timeIntervalSince(clock.now())
    guard seconds > 0 else { return poll }
    return min(.seconds(seconds), poll)
  }
}

/// Fans the detected state out to any number of `AsyncStream` subscribers; each one starts with
/// the state at subscription time and then sees every change.
final class MeetingStateBroadcaster: Sendable {
  private struct State {
    var current = MeetingState.inactive
    var nextID = 0
    var subscribers: [Int: AsyncStream<MeetingState>.Continuation] = [:]
  }

  private let state = Mutex(State())

  var current: MeetingState { state.withLock { $0.current } }

  func stream() -> AsyncStream<MeetingState> {
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

  func publish(_ next: MeetingState) {
    let subscribers = state.withLock { state -> [AsyncStream<MeetingState>.Continuation] in
      guard state.current != next else { return [] }
      state.current = next
      return Array(state.subscribers.values)
    }
    for subscriber in subscribers { subscriber.yield(next) }
  }
}
