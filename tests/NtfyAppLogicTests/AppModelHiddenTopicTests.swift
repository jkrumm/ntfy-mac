import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

/// The menu bar follows "hide from All messages": no unread count, badge or recent row for the
/// topic, while its messages still wait for an acknowledgement.
@MainActor @Suite struct AppModelHiddenTopicTests {
  private func rig() async -> ModelRig {
    let config = Config(topicSettings: ["updates": TopicSettings(hideFromAll: true)])
    let rig = ModelRig(pipeline: PipelineFixture(config: config))
    _ = try? await rig.pipeline.history.append(
      rig.pipeline.message("u1", topic: "updates", age: 3, priority: .max))
    _ = try? await rig.pipeline.history.append(rig.pipeline.message("u2", topic: "updates", age: 2))
    _ = try? await rig.pipeline.history.append(rig.pipeline.message("a1", topic: "alerts", age: 1))
    return rig
  }

  @Test func theUnreadCountBadgeAndRecentRowsLeaveItOut() async {
    let rig = await rig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.recent.count == 1 })
    #expect(rig.model.recent.map(\.key.id) == ["a1"])
    #expect(rig.model.unreadCount == 1)
    #expect(rig.model.badgeText == "1")
    rig.model.stop()
  }

  @Test func itsUrgentMessagesStillCountAsWaitingForAnAcknowledgement() async {
    let rig = await rig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.unacknowledgedCount == 1 })
    rig.model.stop()
  }

  @Test func showingItAgainBringsItBackThroughTheConfigSignal() async {
    let rig = await rig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.recent.count == 1 })
    await rig.pipeline.config.update { $0.topicSettings["updates"] = nil }
    rig.configChanges.fire()
    #expect(await rig.eventually { rig.model.recent.count == 3 })
    #expect(rig.model.unreadCount == 3)
    rig.model.stop()
  }
}
