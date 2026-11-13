import Foundation
import NtfyCore
import Testing

/// What the History window needs from a store, run against both implementations.
@Suite struct HistoryBrowsingContractTests {
  @Test(arguments: Backend.allCases)
  func countHonoursEveryFilterAndIgnoresPaging(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(
      rig.message("1", topic: "a", at: 0, body: "deploy ok", priority: .low))
    try await rig.store.append(
      rig.message("2", topic: "a", at: 10, body: "deploy failed", priority: .high))
    try await rig.store.append(rig.message("3", topic: "b", at: 20, body: "disk", priority: .max))
    try await rig.store.append(rig.message("4", topic: "b", at: 21, sequenceID: "3"))
    try await rig.store.markRead(topic: "a", id: "2")

    func count(_ query: HistoryQuery) async throws -> Int { try await rig.store.count(query) }
    #expect(try await count(HistoryQuery()) == 3)
    #expect(try await count(HistoryQuery(limit: 1, offset: 1)) == 3)
    #expect(try await count(HistoryQuery(topic: "a")) == 2)
    #expect(try await count(HistoryQuery(unreadOnly: true)) == 2)
    #expect(try await count(HistoryQuery(minPriority: .high)) == 1)
    #expect(try await count(HistoryQuery(since: rig.clock.now().addingTimeInterval(5))) == 2)
    #expect(try await count(HistoryQuery(until: rig.clock.now().addingTimeInterval(10))) == 2)
    #expect(try await count(HistoryQuery(until: rig.clock.now().addingTimeInterval(-1))) == 0)
    #expect(try await count(HistoryQuery(text: "deploy")) == 2)
    #expect(try await count(HistoryQuery(topic: "a", text: "failed")) == 1)
    #expect(try await count(HistoryQuery(text: "\"")) == 0)
    #expect(try await count(HistoryQuery(topic: "missing")) == 0)
  }

  @Test(arguments: Backend.allCases)
  func unacknowledgedFromListsWhatStillWaitsAndComposesWithTheOtherFilters(_ backend: Backend)
    async throws
  {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", topic: "a", at: 0, body: "disk", priority: .max))
    try await rig.store.append(rig.message("2", topic: "b", at: 10, body: "disk", priority: .high))
    try await rig.store.append(rig.message("3", topic: "a", at: 20, priority: .max))
    try await rig.store.append(rig.message("4", topic: "a", at: 30, priority: .default))
    try await rig.store.acknowledge(topic: "a", id: "3")

    func ids(_ query: HistoryQuery) async throws -> [String] {
      try await rig.store.entries(query).map(\.message.id)
    }
    #expect(try await ids(HistoryQuery(unacknowledgedFrom: .high)) == ["2", "1"])
    #expect(try await ids(HistoryQuery(unacknowledgedFrom: .max)) == ["1"])
    #expect(try await ids(HistoryQuery(unacknowledgedFrom: .default)) == ["4", "2", "1"])
    #expect(try await ids(HistoryQuery(minPriority: .max, unacknowledgedFrom: .high)) == ["1"])
    #expect(try await ids(HistoryQuery(text: "disk", unacknowledgedFrom: .high)) == ["2", "1"])
    #expect(try await rig.store.count(HistoryQuery(limit: 1, unacknowledgedFrom: .high)) == 2)
    // The same rule as `unacknowledged(minPriority:)`.
    let waiting = try await rig.store.unacknowledged(minPriority: .high).map(\.message.id)
    #expect(Set(waiting) == Set(try await ids(HistoryQuery(unacknowledgedFrom: .high))))
  }

  @Test(arguments: Backend.allCases)
  func topicsSummariseVisibleMessagesNewestFirst(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    #expect(try await rig.store.topics().isEmpty)
    try await rig.store.append(rig.message("1", topic: "old", at: 0))
    try await rig.store.append(rig.message("2", topic: "busy", at: 10))
    try await rig.store.append(rig.message("3", topic: "busy", at: 30))
    try await rig.store.append(rig.message("4", topic: "busy", at: 40, sequenceID: "3"))
    try await rig.store.append(rig.message("5", topic: "gone", at: 50))
    try await rig.store.append(rig.message("6", topic: "tie", at: 20))
    try await rig.store.append(rig.message("7", topic: "alpha", at: 20))
    try await rig.store.markRead(topic: "busy", id: "2")
    try await rig.store.withdraw(topic: "gone", sequenceID: "5")

    let start = rig.clock.now()
    let topics = try await rig.store.topics()
    #expect(topics.map(\.topic) == ["busy", "alpha", "tie", "old"])
    let busy = try #require(topics.first)
    #expect(busy.total == 2)
    #expect(busy.unread == 1)
    #expect(busy.newest == start.addingTimeInterval(40))
    #expect(topics.last?.unread == 1)
  }

  @Test(arguments: Backend.allCases)
  func markUnreadReversesReadButKeepsAcknowledgement(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1"))
    try await rig.store.acknowledge(topic: "alerts", id: "1")
    try await rig.store.markUnread(topic: "alerts", id: "1")
    let stored = try #require(try await rig.store.message(topic: "alerts", id: "1"))
    #expect(!stored.isRead)
    #expect(stored.isAcknowledged)
    #expect(try await rig.store.topics().first?.unread == 1)
    try await rig.store.markRead(topic: "alerts", id: "1")
    #expect(try await rig.store.message(topic: "alerts", id: "1")?.isRead == true)
  }

  @Test(arguments: Backend.allCases)
  func theContentTypeRoundTrips(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", at: 0, contentType: "text/markdown"))
    try await rig.store.append(rig.message("2", at: 1))
    let found = try #require(try await rig.store.message(topic: "alerts", id: "1"))
    #expect(found.message.contentType == "text/markdown")
    #expect(found.message.isMarkdown)
    #expect(try await rig.store.message(topic: "alerts", id: "2")?.message.isMarkdown == false)
  }
}
