import NtfyCore

/// Suspends callers until opened. A cancelled waiter returns at once, like a real network call.
actor Gate {
  private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
  private var nextID = 0
  private var isOpen = false

  var waiterCount: Int { waiters.count }

  func wait() async {
    if isOpen { return }
    let id = nextID
    nextID += 1
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if isOpen || Task.isCancelled {
          continuation.resume()
        } else {
          waiters[id] = continuation
        }
      }
    } onCancel: {
      Task { await self.release(id) }
    }
  }

  func open() {
    isOpen = true
    for id in Array(waiters.keys) { release(id) }
  }

  private func release(_ id: Int) {
    waiters.removeValue(forKey: id)?.resume()
  }
}

/// A topic source whose chosen calls (1-based) wait on a gate, then answer or fail.
actor ProgrammableTopicSource: TopicSource {
  enum Behavior: Sendable {
    case answer([String])
    case fail(NtfyError)
  }

  let gate = Gate()
  private(set) var callCount = 0
  private let topics: [String]
  private var held: [Int: Behavior] = [:]
  private var immediate: [Int: Behavior] = [:]

  init(topics: [String]) {
    self.topics = topics
  }

  /// The given call waits for `gate.open()` and then behaves as `behavior`.
  func hold(call: Int, then behavior: Behavior) { held[call] = behavior }

  /// The given call answers at once with `behavior`.
  func script(call: Int, _ behavior: Behavior) { immediate[call] = behavior }

  func subscribedTopics() async throws(NtfyError) -> [String] {
    callCount += 1
    let call = callCount
    if let behavior = held[call] {
      await gate.wait()
      return try resolve(behavior)
    }
    return try resolve(immediate[call] ?? .answer(topics))
  }

  private func resolve(_ behavior: Behavior) throws(NtfyError) -> [String] {
    switch behavior {
    case .answer(let names): return names
    case .fail(let error): throw error
    }
  }
}

/// A poller whose first poll waits on a gate.
actor HoldingPoller: MessagePoller {
  let gate = Gate()
  private(set) var pollCount = 0

  func poll(topics: [String], since: String?) async throws(NtfyError) -> [NtfyMessage] {
    pollCount += 1
    await gate.wait()
    return []
  }
}
