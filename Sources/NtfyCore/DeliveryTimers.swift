import Foundation

/// The clock-based timers behind a delivered notification: auto-dismiss and re-alert. Each is
/// keyed by notification identifier, so scheduling again replaces the earlier one. A value type;
/// the delivery actor owns it.
struct DeliveryTimers {
  enum Kind: Hashable { case dismiss, realert }

  struct Key: Hashable {
    let kind: Kind
    let identifier: String
  }

  private struct Entry {
    let generation: Int
    let ref: MessageRef
    let task: Task<Void, Never>
  }

  private var entries: [Key: Entry] = [:]
  private var generations = 0

  var isEmpty: Bool { entries.isEmpty }

  /// Sleeps `after` on `clock`, then calls `fire` with the generation to hand to `finish`. A
  /// cancelled sleep never fires.
  mutating func schedule(
    _ key: Key, ref: MessageRef, after: Duration, clock: any Clock,
    fire: @escaping @Sendable (Int) async -> Void
  ) {
    generations += 1
    let generation = generations
    entries[key]?.task.cancel()
    let task = Task {
      do { try await clock.sleep(for: after) } catch { return }
      await fire(generation)
    }
    entries[key] = Entry(generation: generation, ref: ref, task: task)
  }

  func has(_ key: Key) -> Bool { entries[key] != nil }

  func isCurrent(_ key: Key, generation: Int) -> Bool {
    entries[key]?.generation == generation
  }

  /// True once for the timer that is still current; it is gone afterwards.
  mutating func finish(_ key: Key, generation: Int) -> Bool {
    guard isCurrent(key, generation: generation) else { return false }
    entries[key] = nil
    return true
  }

  /// Cancels every timer of the notification.
  mutating func cancel(identifier: String) {
    cancel { $0.key.identifier == identifier }
  }

  /// Cancels the timers that belong to this message only.
  mutating func cancel(ref: MessageRef) {
    cancel { $0.value.ref == ref }
  }

  /// The notification a message is shown under, while one of its timers runs.
  func identifier(for ref: MessageRef) -> String? {
    entries.first { $0.value.ref == ref }?.key.identifier
  }

  /// Cancels everything and returns the tasks, so the caller can wait for them.
  mutating func cancelAll() -> [Task<Void, Never>] {
    let tasks = entries.values.map(\.task)
    for task in tasks { task.cancel() }
    entries = [:]
    return tasks
  }

  private mutating func cancel(where matches: ((key: Key, value: Entry)) -> Bool) {
    for entry in entries where matches(entry) {
      entry.value.task.cancel()
      entries[entry.key] = nil
    }
  }
}
