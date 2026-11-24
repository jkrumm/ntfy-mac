import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

/// A topic hidden from "All messages": out of that list, its count and the search there, but in
/// its own view and in the Unacknowledged view. And the sidebar menu's writes to the config.
@MainActor @Suite struct HistoryModelHideFromAllTests {
  private func rig(hidden: Bool = true) async -> HistoryModelRig {
    let config = Config(
      reAlertMinPriority: 4,
      topicSettings: ["updates": TopicSettings(emoji: "📦", hideFromAll: hidden)])
    let rig = HistoryModelRig(pipeline: PipelineFixture(config: config))
    await rig.add("u1", topic: "updates", age: 30, body: "release notes", priority: .max)
    await rig.add("u2", topic: "updates", age: 20, body: "release notes")
    await rig.add("a1", topic: "alerts", age: 10, body: "release blocked")
    await rig.start()
    return rig
  }

  @Test func allMessagesLeavesTheTopicOutOfTheListTheCountAndTheUnreadBadge() async {
    let rig = await rig()
    #expect(rig.model.scope == .all)
    #expect(rig.ids() == ["a1"])
    #expect(rig.model.resultCount == 1)
    #expect(rig.model.totalUnread == 1)
    #expect(rig.model.totalMessages == 1)
    // The topic keeps its own row and its own numbers in the sidebar.
    #expect(rig.model.topics.first { $0.topic == "updates" }?.unread == 2)
    rig.model.stop()
  }

  @Test func theTopicsOwnViewStillListsIt() async {
    let rig = await rig()
    rig.model.show(.topic("updates"))
    await rig.model.refresh()
    #expect(rig.ids() == ["u2", "u1"])
    #expect(rig.model.resultCount == 2)
    rig.model.stop()
  }

  @Test func theUnacknowledgedViewStillListsIt() async {
    let rig = await rig()
    rig.model.show(.needsAcknowledgement)
    await rig.model.refresh()
    #expect(rig.ids() == ["u1"])
    rig.model.stop()
  }

  @Test func searchInAllMessagesSkipsItToo() async {
    let rig = await rig()
    rig.model.searchText = "release"
    await rig.model.refresh()
    _ = await rig.eventually { rig.model.resultCount == 1 }
    #expect(rig.ids() == ["a1"])
    rig.model.stop()
  }

  @Test func withoutTheSettingAllMessagesListsEverything() async {
    let rig = await rig(hidden: false)
    #expect(rig.ids() == ["a1", "u2", "u1"])
    #expect(rig.model.totalUnread == 3)
    rig.model.stop()
  }

  @Test func showingTheTopicAgainPutsItBackInAllMessages() async {
    let rig = await rig()
    await rig.model.setHideFromAll(false, topic: "updates")
    #expect(rig.ids() == ["a1", "u2", "u1"])
    #expect(await rig.pipeline.config.load().topicSettings["updates"] == TopicSettings(emoji: "📦"))
    await rig.model.setHideFromAll(true, topic: "updates")
    #expect(rig.ids() == ["a1"])
    rig.model.stop()
  }

  @Test func markAllReadOnAllMessagesLeavesAHiddenTopicAlone() async {
    let rig = await rig()
    await rig.model.markAllRead(topic: nil)
    #expect(rig.model.topics.first { $0.topic == "alerts" }?.unread == 0)
    #expect(rig.model.topics.first { $0.topic == "updates" }?.unread == 2)
    await rig.model.markAllRead(topic: "updates")
    #expect(rig.model.topics.first { $0.topic == "updates" }?.unread == 0)
    #expect(rig.model.shownInAll.map(\.topic) == ["alerts"])
    rig.model.stop()
  }

  // MARK: The sidebar menu's writes

  @Test func theMenuWritesMuteAndMinimumPriorityToTheConfig() async {
    let rig = await rig()
    await rig.model.setMute(true, topic: "alerts")
    await rig.model.setMinPriority(4, topic: "alerts")
    #expect(
      await rig.pipeline.config.load().topicSettings["alerts"]
        == TopicSettings(mute: true, minPriority: 4))
    #expect(rig.model.settings(for: "alerts").mute)
    await rig.model.setMute(false, topic: "alerts")
    await rig.model.setMinPriority(nil, topic: "alerts")
    #expect(await rig.pipeline.config.load().topicSettings["alerts"] == nil)
    rig.model.stop()
  }

  @Test func theEmojiIsTrimmedAndBlankRemovesIt() async {
    let rig = await rig()
    #expect(rig.model.emoji(for: "updates") == "📦")
    await rig.model.setEmoji("  🚨 ", topic: "alerts")
    #expect(rig.model.emoji(for: "alerts") == "🚨")
    #expect(await rig.pipeline.config.load().topicSettings["alerts"]?.emoji == "🚨")
    await rig.model.setEmoji("   ", topic: "alerts")
    #expect(rig.model.emoji(for: "alerts") == nil)
    #expect(await rig.pipeline.config.load().topicSettings["alerts"] == nil)
    rig.model.stop()
  }

  @Test func aConfigChangeFromElsewhereIsPickedUp() async {
    let signal = ChangeSignal()
    let pipeline = PipelineFixture()
    let source = ManualPipelineSource()
    source.set(pipeline.handles)
    let model = HistoryModel(
      source: source, opener: RecordingLinkOpener(), clock: pipeline.clock,
      config: pipeline.config, calendar: HistoryModelRig.utc,
      configChanges: { signal.stream() })
    _ = try? await pipeline.history.append(pipeline.message("m1", topic: "updates"))
    model.start()
    for _ in 0..<200_000 where !model.isAvailable { await Task.yield() }
    await model.refresh()
    #expect(model.rows.count == 1)
    await pipeline.config.update {
      $0.topicSettings["updates"] = TopicSettings(hideFromAll: true)
    }
    signal.fire()
    for _ in 0..<200_000 where !model.rows.isEmpty { await Task.yield() }
    #expect(model.rows.isEmpty)
    model.stop()
  }
}
