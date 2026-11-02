import Foundation
import Testing

@testable import NtfyCore

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

private func message(_ id: String, priority: Int = 3) -> DeliveryQueue.Payload {
  .message(
    NtfyMessage(
      id: id, topic: "t", time: epoch, body: "b", priority: Priority(clamping: priority)),
    repeatsLeft: nil)
}

private func drainedIDs(_ queue: inout DeliveryQueue) -> [String] {
  var ids: [String] = []
  while let item = queue.next() { ids.append(item.payload.ref?.id ?? "summary") }
  return ids
}

@Suite struct DeliveryQueueOrderTests {
  @Test func higherPriorityComesFirst() {
    var queue = DeliveryQueue()
    queue.enqueue(message("p1", priority: 1))
    queue.enqueue(message("p5", priority: 5))
    queue.enqueue(message("p3", priority: 3))
    #expect(drainedIDs(&queue) == ["p5", "p3", "p1"])
  }

  @Test func arrivalOrderBreaksTies() {
    var queue = DeliveryQueue()
    for id in ["first", "second", "third"] { queue.enqueue(message(id)) }
    #expect(drainedIDs(&queue) == ["first", "second", "third"])
  }

  @Test func aLateUrgentItemJumpsTheWaitingOnes() {
    var queue = DeliveryQueue()
    queue.enqueue(message("low", priority: 1))
    queue.enqueue(message("mid", priority: 3))
    let first = queue.next()
    #expect(first?.payload.ref?.id == "mid")
    queue.enqueue(message("high", priority: 5))
    #expect(drainedIDs(&queue) == ["high", "low"])
  }

  @Test func aRequeuedItemKeepsItsPlaceAmongItsPeers() {
    var queue = DeliveryQueue()
    queue.enqueue(message("a"))
    queue.enqueue(message("b"))
    guard let failed = queue.next() else {
      Issue.record("queue is empty")
      return
    }
    queue.enqueue(message("c"))
    queue.enqueue(message("urgent", priority: 5))
    queue.requeue(failed)
    #expect(drainedIDs(&queue) == ["urgent", "a", "b", "c"])
  }

  @Test func messagesRetryThreeTimesAndSummariesOnce() {
    var queue = DeliveryQueue()
    queue.enqueue(message("m"))
    queue.enqueue(.summary(count: 2, oldestTopic: "t", covers: [], cause: .away))
    guard let first = queue.next(), let second = queue.next() else {
      Issue.record("queue is empty")
      return
    }
    #expect(first.maxAttempts == DeliveryQueue.messageAttempts)
    #expect(second.maxAttempts == DeliveryQueue.systemAttempts)
    #expect(first.priority == 3 && second.priority == 3)
  }

  @Test func removeAndContainsMatchPayloads() {
    var queue = DeliveryQueue()
    queue.enqueue(message("a"))
    queue.enqueue(message("b"))
    #expect(queue.contains { $0.ref?.id == "b" })
    queue.removeAll { $0.ref?.id == "a" }
    #expect(queue.count == 1)
    #expect(!queue.contains { $0.ref?.id == "a" })
  }
}

@Suite struct DeliveryQueuePacingTests {
  @Test func theFirstPostIsImmediate() {
    #expect(DeliveryQueue().delay(at: epoch) == 0)
  }

  @Test func theIntervalRunsFromTheLastAttempt() {
    var queue = DeliveryQueue(minimumInterval: 1.5)
    queue.recordAttempt(at: epoch)
    #expect(queue.delay(at: epoch) == 1.5)
    #expect(queue.delay(at: epoch.addingTimeInterval(0.5)) == 1.0)
    #expect(queue.delay(at: epoch.addingTimeInterval(1.5)) == 0)
    #expect(queue.delay(at: epoch.addingTimeInterval(60)) == 0)
  }
}
