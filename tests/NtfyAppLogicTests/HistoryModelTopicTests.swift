import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct HistoryModelTopicTests {
  @Test func topicsAreOrderedByLatestActivityWithUnreadCounts() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 30)
    await rig.add("b1", topic: "builds", age: 10)
    await rig.add("a2", topic: "alerts", age: 20)
    await rig.add("c1", topic: "cron", age: 50)
    await rig.pipeline.history.markRead(topic: "cron", id: "c1")
    await rig.start()
    #expect(rig.model.topics.map(\.topic) == ["builds", "alerts", "cron"])
    #expect(rig.model.topics.map(\.unread) == [1, 2, 0])
    #expect(rig.model.totalUnread == 3)
    rig.model.stop()
  }

  @Test func aNewMessageMovesItsTopicToTheTop() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 30)
    await rig.add("b1", topic: "builds", age: 10)
    await rig.start()
    #expect(rig.model.topics.first?.topic == "builds")
    await rig.add("a2", topic: "alerts", age: 1)
    await rig.model.refresh()
    #expect(rig.model.topics.map(\.topic) == ["alerts", "builds"])
    rig.model.stop()
  }

  @Test func theTopicListIgnoresTheTopicSelection() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 2)
    await rig.add("b1", topic: "builds", age: 1)
    await rig.start()
    rig.model.selectedTopic = "alerts"
    await rig.model.refresh()
    #expect(rig.model.topics.count == 2)
    #expect(rig.model.rows.map(\.key.id) == ["a1"])
    rig.model.stop()
  }

  @Test func theUrgentMarkerNeedsAnUnacknowledgedUrgentMessage() async {
    let rig = HistoryModelRig()
    await rig.add("hot", topic: "alerts", age: 5, priority: .max)
    await rig.add("calm", topic: "builds", age: 4, priority: .default)
    await rig.add("done", topic: "cron", age: 3, priority: .max)
    await rig.pipeline.history.acknowledge(topic: "cron", id: "done")
    await rig.start()
    #expect(rig.model.urgentTopics == ["alerts"])
    rig.model.stop()
  }

  @Test func theLogIsNewestFirstAndGroupedByDay() async {
    let rig = HistoryModelRig()
    await rig.add("old", age: 3 * 86_400)
    await rig.add("mid", age: 100)
    await rig.add("new", age: 10)
    await rig.start()
    #expect(rig.model.rows.map(\.key.id) == ["new", "mid", "old"])
    #expect(rig.model.days.count == 2)
    #expect(rig.model.days.first?.rows.map(\.key.id) == ["new", "mid"])
    rig.model.stop()
  }

  @Test func pagingExtendsTheLogBackwardsOnly() async {
    let rig = HistoryModelRig(pageSize: 2)
    for index in 1...5 { await rig.add("m\(index)", age: Double(60 - index)) }
    await rig.start()
    #expect(rig.model.rows.map(\.key.id) == ["m5", "m4"])
    #expect(rig.model.hasMore)
    await rig.model.loadMore()
    #expect(rig.model.rows.map(\.key.id) == ["m5", "m4", "m3", "m2"])
    rig.model.stop()
  }

  @Test func narrowingExcludesTheTopicAndClearingKeepsIt() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts")
    await rig.start()
    rig.model.selectedTopic = "alerts"
    #expect(!rig.model.isNarrowing)
    rig.model.unreadOnly = true
    rig.model.minPriority = .high
    #expect(rig.model.isNarrowing)
    rig.model.clearNarrowing()
    #expect(!rig.model.isNarrowing)
    #expect(rig.model.selectedTopic == "alerts")
    rig.model.stop()
  }

  @Test func selectingMarksReadButLoadingNeverDoes() async {
    let rig = HistoryModelRig()
    await rig.add("a", age: 2)
    await rig.add("b", age: 1)
    await rig.start()
    await rig.model.refresh()
    #expect(rig.model.rows.allSatisfy { !$0.isRead })
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    #expect(rig.model.rows.filter(\.isRead).map(\.key.id) == ["a"])
    rig.model.stop()
  }

  @Test func acknowledgingNeedsTheRowToBePending() async {
    let rig = HistoryModelRig()
    await rig.add("hot", priority: .max)
    await rig.add("calm", age: 1)
    await rig.start()
    let pending = rig.model.rows.filter { rig.model.canAcknowledge($0) }.map(\.key.id)
    #expect(pending == ["hot"])
    rig.model.stop()
  }
}
