import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

/// The "Needs acknowledgement" view: exactly the messages `canAcknowledge` offers a button for.
@MainActor @Suite struct HistoryModelNeedsAcknowledgementTests {
  private func rig() async -> HistoryModelRig {
    let rig = HistoryModelRig(pipeline: PipelineFixture(config: Config(reAlertMinPriority: 4)))
    await rig.add("calm", topic: "ci", age: 40, priority: .default)
    await rig.add("hot-old", topic: "alerts", age: 30, title: "Disk full", priority: .max)
    await rig.add("hot-new", topic: "home", age: 10, title: "Door open", priority: .high)
    await rig.add("hot-done", topic: "alerts", age: 20, priority: .max)
    await rig.pipeline.history.acknowledge(topic: "alerts", id: "hot-done")
    await rig.start()
    return rig
  }

  @Test func listsExactlyTheMessagesTheButtonAppearsOnAcrossTopicsNewestFirst() async {
    let rig = await rig()
    rig.model.selectedTopic = "ci"
    rig.model.show(.needsAcknowledgement)
    _ = await rig.eventually { rig.model.rows.count == 2 }
    await rig.model.refresh()
    let shown = rig.model.rows
    #expect(shown.map(\.key.id) == ["hot-new", "hot-old"])
    #expect(shown.allSatisfy { rig.model.canAcknowledge($0) })
    #expect(rig.model.resultCount == 2)
    #expect(rig.model.pendingCount == 2)
    #expect(rig.model.selectedTopic == nil)
    #expect(rig.model.scope == .needsAcknowledgement)
    #expect(rig.model.scopeTitle == "Unacknowledged")
    rig.model.stop()
  }

  @Test func theBadgeCountsEverythingWhateverTheViewAndFilters() async {
    let rig = await rig()
    #expect(rig.model.pendingCount == 2)
    rig.model.show(.topic("ci"))
    rig.model.minPriority = .max
    await rig.model.refresh()
    #expect(rig.model.pendingCount == 2)
    rig.model.stop()
  }

  @Test func acknowledgingRemovesTheMessageAndLowersTheCount() async {
    let rig = await rig()
    rig.model.show(.needsAcknowledgement)
    await rig.model.refresh()
    await rig.model.select(MessageKey(topic: "alerts", id: "hot-old"))
    await rig.model.acknowledge()
    #expect(rig.model.rows.map(\.key.id) == ["hot-new"])
    #expect(rig.model.pendingCount == 1)
    #expect(rig.model.resultCount == 1)
    // The shown message stays in the detail pane, now acknowledged.
    #expect(rig.model.detail?.isAcknowledged == true)
    await rig.model.acknowledge(MessageKey(topic: "home", id: "hot-new"))
    #expect(rig.model.rows.isEmpty)
    #expect(rig.model.pendingCount == 0)
    rig.model.stop()
  }

  @Test func theOtherFiltersStillApply() async {
    let rig = await rig()
    rig.model.show(.needsAcknowledgement)
    rig.model.minPriority = .max
    await rig.model.refresh()
    #expect(rig.model.rows.map(\.key.id) == ["hot-old"])
    rig.model.minPriority = nil
    rig.model.searchText = "door"
    _ = await rig.eventually { rig.model.rows.map(\.key.id) == ["hot-new"] }
    #expect(rig.model.rows.map(\.key.id) == ["hot-new"])
    rig.model.stop()
  }

  @Test func theThresholdFollowsTheConfiguredMinimum() async {
    let rig = HistoryModelRig(pipeline: PipelineFixture(config: Config(reAlertMinPriority: 4)))
    await rig.add("default", priority: .default)
    await rig.add("high", age: 1, priority: .high)
    await rig.start()
    rig.model.show(.needsAcknowledgement)
    await rig.model.refresh()
    #expect(rig.model.rows.map(\.key.id) == ["high"])
    rig.model.stop()
  }

  @Test func theViewIsAScopeNotANarrowingAndResetLeavesIt() async {
    let rig = await rig()
    rig.model.show(.needsAcknowledgement)
    #expect(!rig.model.isNarrowing)
    #expect(rig.model.isFiltering)
    rig.model.unreadOnly = true
    rig.model.clearNarrowing()
    #expect(rig.model.scope == .needsAcknowledgement)
    rig.model.show(.topic("ci"))
    #expect(!rig.model.needsAcknowledgementOnly)
    #expect(rig.model.scope == .topic("ci"))
    rig.model.show(.needsAcknowledgement)
    rig.model.resetFilters()
    #expect(rig.model.scope == .all)
    rig.model.stop()
  }

  @Test func aViewWithNothingToAcknowledgeIsEmpty() async {
    let rig = HistoryModelRig()
    await rig.add("calm")
    await rig.start()
    rig.model.show(.needsAcknowledgement)
    await rig.model.refresh()
    #expect(rig.model.rows.isEmpty)
    #expect(rig.model.days.isEmpty)
    #expect(rig.model.resultCount == 0)
    #expect(rig.model.pendingCount == 0)
    rig.model.stop()
  }
}
