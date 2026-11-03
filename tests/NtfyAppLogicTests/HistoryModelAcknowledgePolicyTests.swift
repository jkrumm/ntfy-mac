import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct HistoryModelAcknowledgePolicyTests {
  @Test func onlyMessagesAtTheReAlertMinimumNeedAnAcknowledgement() async {
    let rig = HistoryModelRig()
    await rig.add("normal", priority: .default)
    await rig.add("high", priority: .high)
    await rig.add("urgent", priority: .max)
    await rig.start()
    let pending = rig.model.thread.filter { rig.model.canAcknowledge($0.detail) }.map(\.key.id)
    #expect(pending == ["urgent"])
    // The sidebar's urgent marker follows the same threshold, so it can always be cleared.
    #expect(rig.model.conversation("alerts")?.hasUrgent == true)
    await rig.model.acknowledge(MessageKey(topic: "alerts", id: "urgent"))
    #expect(rig.model.thread.allSatisfy { !rig.model.canAcknowledge($0.detail) })
    #expect(rig.model.conversation("alerts")?.hasUrgent == false)
    rig.model.stop()
  }

  @Test func theThresholdFollowsTheConfiguredMinimum() async {
    let rig = HistoryModelRig(pipeline: PipelineFixture(config: Config(reAlertMinPriority: 4)))
    await rig.add("high", priority: .high)
    await rig.start()
    #expect(rig.model.canAcknowledge(rig.model.thread[0].detail))
    rig.model.stop()
  }
}
