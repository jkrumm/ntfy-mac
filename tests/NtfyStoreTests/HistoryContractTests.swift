import Foundation
import NtfyCore
import Testing

/// Behaviour both history stores must share.
@Suite struct HistoryContractTests {
  @Test(arguments: Backend.allCases)
  func appendReportsDuplicates(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    #expect(try await rig.store.append(rig.message("1")) == true)
    #expect(try await rig.store.append(rig.message("1")) == false)
    #expect(try await rig.store.append(rig.message("1", topic: "other")) == true)
    #expect(try await rig.store.recent(limit: 10).count == 2)
  }

  @Test(arguments: Backend.allCases)
  func recentIsNewestFirstAndTracksCursor(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    for (index, id) in ["a", "b", "c"].enumerated() {
      try await rig.store.append(rig.message(id, at: Double(index)))
    }
    #expect(try await rig.store.recent(limit: 2).map(\.id) == ["c", "b"])
    #expect(try await rig.store.recent(limit: 0).isEmpty)
    #expect(try await rig.store.lastMessageID() == "c")
  }

  @Test(arguments: Backend.allCases)
  func emptyStoreHasNoCursor(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    #expect(try await rig.store.lastMessageID() == nil)
  }

  @Test(arguments: Backend.allCases)
  func newerSequenceMemberSupersedesOlder(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", at: 0, body: "first", sequenceID: "seq"))
    try await rig.store.append(rig.message("2", at: 5, body: "second", sequenceID: "seq"))
    try await rig.store.append(rig.message("3", topic: "other", at: 6, sequenceID: "seq"))
    #expect(try await rig.store.recent(limit: 10).map(\.id) == ["3", "2"])
    #expect(try await rig.store.entries(HistoryQuery(topic: "alerts")).map(\.message.id) == ["2"])
  }

  @Test(arguments: Backend.allCases)
  func sequenceDefaultsToTheMessageId(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", at: 0))
    try await rig.store.append(rig.message("2", at: 1, sequenceID: "1"))
    #expect(try await rig.store.recent(limit: 10).map(\.id) == ["2"])
  }

  @Test(arguments: Backend.allCases)
  func withdrawHidesTheWholeSequence(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", at: 0, sequenceID: "seq"))
    try await rig.store.append(rig.message("2", at: 1, sequenceID: "seq"))
    try await rig.store.append(rig.message("3", at: 2))
    try await rig.store.withdraw(topic: "alerts", sequenceID: "seq")
    #expect(try await rig.store.recent(limit: 10).map(\.id) == ["3"])
    #expect(try await rig.store.unnotified(limit: 10).map(\.id) == ["3"])
    #expect(try await rig.store.append(rig.message("1", at: 0, sequenceID: "seq")) == false)
    #expect(try await rig.store.lastMessageID() == "3")
  }

  @Test(arguments: Backend.allCases)
  func markClearedReadsAndAcknowledges(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", sequenceID: "seq"))
    try await rig.store.append(rig.message("2", topic: "other", sequenceID: "seq"))
    try await rig.store.snooze(
      topic: "alerts", id: "1", until: rig.clock.now().addingTimeInterval(60))
    try await rig.store.markCleared(topic: "alerts", sequenceID: "seq")

    let entries = try await rig.store.entries(HistoryQuery())
    let cleared = try #require(entries.first { $0.message.id == "1" })
    #expect(cleared.isRead)
    #expect(cleared.isAcknowledged)
    #expect(cleared.remindAt == nil)
    let untouched = try #require(entries.first { $0.message.id == "2" })
    #expect(!untouched.isRead)
    #expect(try await rig.store.unacknowledged(minPriority: .min).map(\.message.id) == ["2"])
  }

  @Test(arguments: Backend.allCases)
  func searchMatchesPrefixesInTitleAndBody(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", at: 0, title: "Backup finished", body: "all good"))
    try await rig.store.append(rig.message("2", at: 1, body: "Disk almost full on host"))
    #expect(try await rig.store.entries(HistoryQuery(text: "back")).map(\.message.id) == ["1"])
    #expect(try await rig.store.entries(HistoryQuery(text: "DISK full")).map(\.message.id) == ["2"])
    #expect(try await rig.store.entries(HistoryQuery(text: "good")).map(\.message.id) == ["1"])
    #expect(try await rig.store.entries(HistoryQuery(text: "nothing")).isEmpty)
  }

  @Test(
    arguments: Backend.allCases, ["\"", "*", "\"unterminated", "a AND", "(", "NEAR(", "   ", ":"])
  func searchSurvivesSpecialCharacters(_ backend: Backend, _ text: String) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", body: "plain words a"))
    let found = try await rig.store.entries(HistoryQuery(text: text))
    #expect(found.count <= 1)
  }

  @Test(arguments: Backend.allCases)
  func searchFindsWordsNextToQuotes(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", body: "say \"hello\" now"))
    #expect(try await rig.store.entries(HistoryQuery(text: "\"hello\"")).map(\.message.id) == ["1"])
  }

  @Test(arguments: Backend.allCases)
  func filtersNarrowTheResult(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", topic: "a", at: 0, priority: .low))
    try await rig.store.append(rig.message("2", topic: "a", at: 10, priority: .high))
    try await rig.store.append(rig.message("3", topic: "b", at: 20, priority: .max))
    try await rig.store.markRead(topic: "a", id: "2")

    func ids(_ query: HistoryQuery) async throws -> [String] {
      try await rig.store.entries(query).map(\.message.id)
    }
    #expect(try await ids(HistoryQuery()) == ["3", "2", "1"])
    #expect(try await ids(HistoryQuery(topic: "a")) == ["2", "1"])
    #expect(try await ids(HistoryQuery(unreadOnly: true)) == ["3", "1"])
    #expect(try await ids(HistoryQuery(minPriority: .high)) == ["3", "2"])
    let since = rig.clock.now().addingTimeInterval(5)
    #expect(try await ids(HistoryQuery(since: since)) == ["3", "2"])
    #expect(try await ids(HistoryQuery(limit: 1, offset: 1)) == ["2"])
    #expect(try await ids(HistoryQuery(limit: 0)).isEmpty)
    #expect(
      try await ids(HistoryQuery(topic: "a", unreadOnly: true, minPriority: .default)).isEmpty)
  }

  @Test(arguments: Backend.allCases)
  func searchCombinesWithFilters(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", topic: "a", at: 0, body: "deploy ok"))
    try await rig.store.append(rig.message("2", topic: "b", at: 1, body: "deploy failed"))
    let found = try await rig.store.entries(HistoryQuery(topic: "b", text: "deploy"))
    #expect(found.map(\.message.id) == ["2"])
  }

  @Test(arguments: Backend.allCases)
  func readAndAcknowledgeTrackTheirState(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", at: 0, priority: .max))
    try await rig.store.append(rig.message("2", at: 1))
    try await rig.store.append(rig.message("3", topic: "other", at: 2))

    try await rig.store.markRead(topic: "alerts", id: "1")
    try await rig.store.markAllRead(topic: "alerts")
    let afterRead = try await rig.store.entries(HistoryQuery())
    #expect(afterRead.map(\.isRead) == [false, true, true])
    #expect(afterRead.allSatisfy { !$0.isAcknowledged })

    rig.clock.advance(by: .seconds(30))
    try await rig.store.acknowledge(topic: "alerts", id: "1")
    let acked = try #require(try await rig.store.entries(HistoryQuery(topic: "alerts")).last)
    #expect(acked.isAcknowledged)
    #expect(try await rig.store.unacknowledged(minPriority: .min).map(\.message.id) == ["2", "3"])
    #expect(try await rig.store.unacknowledged(minPriority: .high).isEmpty)
  }

  @Test(arguments: Backend.allCases)
  func acknowledgeMarksUnreadMessagesRead(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1"))
    try await rig.store.acknowledge(topic: "alerts", id: "1")
    let stored = try #require(try await rig.store.entries(HistoryQuery()).first)
    #expect(stored.isRead)
    #expect(stored.isAcknowledged)
  }

  @Test(arguments: Backend.allCases)
  func unnotifiedListsOldestFirstUntilMarked(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    for (index, id) in ["a", "b", "c"].enumerated() {
      try await rig.store.append(rig.message(id, at: Double(index)))
    }
    #expect(try await rig.store.unnotified(limit: 10).map(\.id) == ["a", "b", "c"])
    try await rig.store.markNotified(topic: "alerts", id: "a", at: rig.clock.now())
    #expect(try await rig.store.unnotified(limit: 10).map(\.id) == ["b", "c"])
    #expect(try await rig.store.unnotified(limit: 1).map(\.id) == ["b"])
    let stored = try #require(try await rig.store.entries(HistoryQuery()).last)
    #expect(stored.notifiedAt != nil)
  }

  @Test(arguments: Backend.allCases)
  func snoozedMessagesBecomeDue(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", at: 0))
    try await rig.store.append(rig.message("2", at: 1))
    let start = rig.clock.now()
    try await rig.store.snooze(topic: "alerts", id: "1", until: start.addingTimeInterval(900))
    try await rig.store.snooze(topic: "alerts", id: "2", until: start.addingTimeInterval(300))

    #expect(try await rig.store.dueReminders(now: start).isEmpty)
    let due = try await rig.store.dueReminders(now: start.addingTimeInterval(300))
    #expect(due.map(\.message.id) == ["2"])
    #expect(due.first?.remindAt == start.addingTimeInterval(300))
    let later = try await rig.store.dueReminders(now: start.addingTimeInterval(1000))
    #expect(later.map(\.message.id) == ["2", "1"])

    try await rig.store.clearReminder(topic: "alerts", id: "2")
    try await rig.store.acknowledge(topic: "alerts", id: "1")
    #expect(try await rig.store.dueReminders(now: start.addingTimeInterval(1000)).isEmpty)
  }

  @Test(arguments: Backend.allCases)
  func pruneKeepsTheNewestPerTopic(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    for index in 0..<5 {
      try await rig.store.append(rig.message("a\(index)", topic: "a", at: Double(index)))
    }
    try await rig.store.append(rig.message("b0", topic: "b", at: 0))
    let removed = try await rig.store.prune(
      policy: RetentionPolicy(maxPerTopic: 2), now: rig.clock.now())
    #expect(removed == 3)
    let kept = try await rig.store.entries(HistoryQuery(topic: "a")).map(\.message.id)
    #expect(kept == ["a4", "a3"])
    #expect(try await rig.store.entries(HistoryQuery(topic: "b")).count == 1)
    #expect(try await rig.store.entries(HistoryQuery(text: "body", limit: 50)).count == 3)
  }

  @Test(arguments: Backend.allCases)
  func pruneDropsRowsOlderThanTheMaximumAge(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    let day: TimeInterval = 24 * 60 * 60
    try await rig.store.append(rig.message("old", at: -100 * day))
    try await rig.store.append(rig.message("edge", at: -89 * day))
    try await rig.store.append(rig.message("new", at: 0))
    let removed = try await rig.store.prune(policy: RetentionPolicy(), now: rig.clock.now())
    #expect(removed == 1)
    #expect(try await rig.store.recent(limit: 10).map(\.id) == ["new", "edge"])
    #expect(try await rig.store.prune(policy: RetentionPolicy(), now: rig.clock.now()) == 0)
  }

  @Test func defaultRetentionIsThousandRowsAndNinetyDays() {
    let policy = RetentionPolicy()
    #expect(policy.maxPerTopic == 1000)
    #expect(policy.maxAge == 90 * 24 * 60 * 60)
  }
}
