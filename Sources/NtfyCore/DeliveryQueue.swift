import Foundation

/// Notifications waiting to be shown: highest priority first, oldest first within a priority,
/// and paced so a burst does not flood macOS. A value type; the delivery actor owns it.
struct DeliveryQueue {
  enum Payload: Sendable {
    /// `repeatsLeft` is nil for a first delivery (the config sets the budget) and the number of
    /// re-alerts still to come, this one included, for a re-alert.
    case message(NtfyMessage, repeatsLeft: Int?)
    /// One notification for messages that were missed; `covers` are marked notified once shown.
    case summary(count: Int, oldestTopic: String, covers: [MessageRef])

    var ref: MessageRef? {
      guard case .message(let message, _) = self else { return nil }
      return MessageRef(topic: message.topic, id: message.id)
    }

    var identifier: String? {
      guard case .message(let message, _) = self else { return nil }
      return message.notificationIdentifier
    }

    fileprivate var priority: Int {
      guard case .message(let message, _) = self else { return Priority.default.rawValue }
      return message.priority.rawValue
    }

    fileprivate var maxAttempts: Int {
      guard case .message = self else { return DeliveryQueue.systemAttempts }
      return DeliveryQueue.messageAttempts
    }
  }

  struct Item: Sendable {
    let payload: Payload
    let priority: Int
    let maxAttempts: Int
    /// Order of first arrival; a retry keeps it, so it returns to its place.
    let arrival: Int
    var attempts = 0
  }

  static let messageAttempts = 3
  static let systemAttempts = 1

  /// Seconds between two posts.
  let minimumInterval: TimeInterval
  private var items: [Item] = []
  private var arrivals = 0
  private var lastAttempt: Date?

  init(minimumInterval: TimeInterval = 1.5) {
    self.minimumInterval = minimumInterval
  }

  var isEmpty: Bool { items.isEmpty }
  var count: Int { items.count }
  var payloads: [Payload] { items.map(\.payload) }

  mutating func enqueue(_ payload: Payload) {
    arrivals += 1
    insert(
      Item(
        payload: payload, priority: payload.priority, maxAttempts: payload.maxAttempts,
        arrival: arrivals))
  }

  /// Puts a failed item back at its sorted position.
  mutating func requeue(_ item: Item) {
    insert(item)
  }

  /// The item to show next.
  mutating func next() -> Item? {
    items.isEmpty ? nil : items.removeFirst()
  }

  mutating func removeAll(where shouldRemove: (Payload) -> Bool) {
    items.removeAll { shouldRemove($0.payload) }
  }

  func contains(where predicate: (Payload) -> Bool) -> Bool {
    items.contains { predicate($0.payload) }
  }

  /// Starts the pause before the next post; call after every attempt, successful or not.
  mutating func recordAttempt(at time: Date) {
    lastAttempt = time
  }

  /// Seconds to wait before the next post may go out; zero for the very first.
  func delay(at now: Date) -> TimeInterval {
    guard let lastAttempt else { return 0 }
    return max(minimumInterval - now.timeIntervalSince(lastAttempt), 0)
  }

  private mutating func insert(_ item: Item) {
    let index =
      items.firstIndex {
        $0.priority < item.priority || ($0.priority == item.priority && $0.arrival > item.arrival)
      } ?? items.endIndex
    items.insert(item, at: index)
  }
}
