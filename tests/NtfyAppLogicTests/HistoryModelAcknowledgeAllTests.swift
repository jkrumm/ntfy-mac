import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

/// "Acknowledge All" in the History window: every view, the Unacknowledged view and one topic.
@MainActor @Suite struct HistoryModelAcknowledgeAllTests {
  private func rig() async -> HistoryModelRig {
    let rig = HistoryModelRig(pipeline: PipelineFixture(config: Config(reAlertMinPriority: 4)))
    await rig.add("calm", topic: "ci", age: 50, priority: .default)
    await rig.add("a1", topic: "alerts", age: 40, priority: .max)
    await rig.add("a2", topic: "alerts", age: 30, priority: .high)
    await rig.add("h1", topic: "home", age: 20, priority: .max)
    await rig.add("done", topic: "home", age: 10, priority: .max)
    await rig.pipeline.history.acknowledge(topic: "home", id: "done")
    await rig.start()
    return rig
  }

  @Test func nilAcknowledgesEveryMessageThatNeedsIt() async {
    let rig = await rig()
    #expect(rig.model.pendingCount == 3)
    await rig.model.acknowledgeAll(topic: nil)
    #expect(rig.model.pendingCount == 0)
    #expect(rig.model.pendingByTopic.isEmpty)
    let all = await rig.pipeline.history.unacknowledged(minPriority: .high)
    #expect(all.isEmpty)
    // A message below the minimum never needed one, so it is left alone.
    let calm = await rig.pipeline.history.message(topic: "ci", id: "calm")
    #expect(calm?.isAcknowledged == false)
    rig.model.stop()
  }

  @Test func theUnacknowledgedViewAcknowledgesWhatItListsAndEmptiesIt() async {
    let rig = await rig()
    rig.model.show(.needsAcknowledgement)
    await rig.model.refresh()
    #expect(rig.model.rows.count == 3)
    #expect(rig.model.pendingCount(in: .needsAcknowledgement) == 3)
    await rig.model.acknowledgeAll(topic: nil)
    #expect(rig.model.rows.isEmpty)
    #expect(rig.model.resultCount == 0)
    #expect(rig.model.pendingCount(in: .needsAcknowledgement) == 0)
    rig.model.stop()
  }

  @Test func aTopicAcknowledgesOnlyItsOwnMessages() async {
    let rig = await rig()
    #expect(rig.model.pendingCount(in: .topic("alerts")) == 2)
    #expect(rig.model.pendingCount(in: .topic("home")) == 1)
    #expect(rig.model.pendingCount(in: .topic("ci")) == 0)
    await rig.model.acknowledgeAll(topic: "alerts")
    #expect(rig.model.pendingCount(in: .topic("alerts")) == 0)
    #expect(rig.model.pendingCount(in: .topic("home")) == 1)
    #expect(rig.model.pendingCount == 1)
    let waiting = await rig.pipeline.history.unacknowledged(minPriority: .high)
    #expect(waiting.map(\.message.id) == ["h1"])
    rig.model.stop()
  }

  @Test func nothingPendingChangesNothing() async {
    let rig = await rig()
    await rig.model.acknowledgeAll(topic: "ci")
    #expect(rig.model.pendingCount == 3)
    rig.model.stop()
  }
}
