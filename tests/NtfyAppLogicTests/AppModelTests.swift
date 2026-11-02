import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct AppModelTests {
  @Test func aPipelineWithoutAServerIsNotConfiguredAndShowsTheHistory() async {
    let rig = ModelRig()
    await rig.pipeline.seed(["a", "b", "c"])
    rig.model.start()
    #expect(await rig.eventually { rig.model.recent.count == 3 })
    #expect(rig.model.connection == .notConfigured)
    #expect(rig.model.recent.map(\.key.id) == ["c", "b", "a"])
    #expect(rig.model.unreadCount == 3)
    #expect(rig.model.unacknowledgedCount == 3)
    rig.model.stop()
  }

  @Test func onlyTheMostRecentMessagesAreRows() async {
    let rig = ModelRig(recentLimit: 2)
    await rig.pipeline.seed(["a", "b", "c"])
    rig.model.start()
    #expect(await rig.eventually { rig.model.unreadCount == 3 })
    #expect(rig.model.recent.map(\.key.id) == ["c", "b"])
    rig.model.stop()
  }

  @Test func aNewMessageShowsUpThroughTheChangeSignal() async {
    let rig = ModelRig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.connection == .notConfigured })
    _ = try? await rig.pipeline.history.append(
      rig.pipeline.message("new", title: "Backup done", priority: .high))
    #expect(await rig.eventually { rig.model.recent.count == 1 })
    let row = rig.model.recent[0]
    #expect(row.title == "Backup done")
    #expect(row.isUrgent)
    #expect(!row.isRead && !row.isAcknowledged)
    #expect(rig.model.badgeText == "1")
    rig.model.stop()
  }

  @Test func acknowledgeMarksTheRowAndLowersTheCounts() async {
    let rig = ModelRig()
    await rig.pipeline.seed(["a", "b"])
    rig.model.start()
    #expect(await rig.eventually { rig.model.recent.count == 2 })
    await rig.model.acknowledge(rig.model.recent[0])
    #expect(rig.model.recent[0].isAcknowledged && rig.model.recent[0].isRead)
    #expect(rig.model.unreadCount == 1)
    #expect(rig.model.unacknowledgedCount == 1)
    rig.model.stop()
  }

  @Test func acknowledgeAllSettlesEverything() async {
    let rig = ModelRig()
    await rig.pipeline.seed(["a", "b", "c"])
    rig.model.start()
    #expect(await rig.eventually { rig.model.unacknowledgedCount == 3 })
    await rig.model.acknowledgeAll()
    #expect(rig.model.unacknowledgedCount == 0)
    #expect(rig.model.unreadCount == 0)
    #expect(rig.model.recent.allSatisfy { $0.isAcknowledged })
    rig.model.stop()
  }

  @Test func markReadKeepsTheMessageUnacknowledged() async {
    let rig = ModelRig()
    await rig.pipeline.seed(["a"])
    rig.model.start()
    #expect(await rig.eventually { rig.model.recent.count == 1 })
    await rig.model.markRead(rig.model.recent[0])
    #expect(rig.model.unreadCount == 0)
    #expect(rig.model.unacknowledgedCount == 1)
    #expect(rig.model.recent[0].isRead && !rig.model.recent[0].isAcknowledged)
    rig.model.stop()
  }

  @Test func theSupervisorStatusDrivesTheConnectionAndTheIcon() async {
    let rig = ModelRig(pipeline: PipelineFixture(withServer: true))
    rig.model.start()
    #expect(await rig.eventually { rig.model.connection == .connecting })
    await rig.pipeline.supervisor?.start()
    #expect(await rig.eventually { !rig.pipeline.stream.calls.isEmpty })
    rig.pipeline.stream.send(.open)
    #expect(await rig.eventually { rig.model.connection == .connected })
    #expect(rig.model.menuBarIcon == .idle)
    rig.pipeline.stream.fail(.unauthorized)
    #expect(
      await rig.eventually {
        rig.model.connection == .needsAttention(reason: "The server rejected the access token")
      })
    #expect(rig.model.menuBarIcon == .attention)
    await rig.pipeline.supervisor?.stop()
    rig.model.stop()
  }

  @Test func reconnectRestartsAHaltedStream() async {
    let rig = ModelRig(pipeline: PipelineFixture(withServer: true))
    rig.model.start()
    await rig.pipeline.supervisor?.start()
    #expect(await rig.eventually { rig.pipeline.stream.calls.count == 1 })
    rig.pipeline.stream.fail(.unauthorized)
    #expect(await rig.eventually { rig.model.connection.needsSettings })
    await rig.model.reconnect()
    #expect(await rig.eventually { rig.pipeline.stream.calls.count == 2 })
    await rig.pipeline.supervisor?.stop()
    rig.model.stop()
  }

  @Test func reattachesWhenThePipelineIsRebuilt() async {
    let rig = ModelRig()
    await rig.pipeline.seed(["old"])
    rig.model.start()
    #expect(await rig.eventually { rig.model.recent.count == 1 })

    let next = PipelineFixture(withServer: true)
    _ = try? await next.history.append(next.message("fresh"))
    rig.source.set(next.handles)
    #expect(await rig.eventually { rig.model.recent.map(\.key.id) == ["fresh"] })
    #expect(rig.model.connection == .connecting)

    _ = try? await next.history.append(next.message("later"))
    #expect(await rig.eventually { rig.model.recent.count == 2 })

    rig.source.set(nil)
    #expect(await rig.eventually { rig.model.connection == .connecting })
    rig.model.stop()
  }

  @Test func theMenuBarIconAndBadgeFollowTheState() async {
    let rig = ModelRig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.connection == .notConfigured })
    #expect(rig.model.menuBarIcon == .idle)
    #expect(rig.model.badgeText == nil)

    await rig.pipeline.seed(["a", "b"])
    #expect(await rig.eventually { rig.model.unreadCount == 2 })
    #expect(rig.model.menuBarIcon == .unread)
    #expect(rig.model.badgeText == "2")

    await rig.model.pause(.indefinitely)
    #expect(rig.model.menuBarIcon == .paused)
    #expect(rig.model.badgeText == "2")
    rig.model.stop()
  }

  @Test func theBadgeCapsAtNinetyNine() async {
    let rig = ModelRig()
    await rig.pipeline.seed((0..<120).map { "m\($0)" })
    rig.model.start()
    #expect(await rig.eventually { rig.model.badgeText != nil })
    #expect(rig.model.badgeText == "99+")
    rig.model.stop()
  }

  @Test func permissionIsReadAtStartAndOnDemand() async {
    let rig = ModelRig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.permission != nil })
    #expect(rig.model.permission?.problems.isEmpty == true)
    await rig.permission.set(NotificationPermission(authorization: .denied))
    await rig.model.refreshPermission()
    #expect(rig.model.permission?.problems == [.denied])
    rig.model.stop()
  }
}
