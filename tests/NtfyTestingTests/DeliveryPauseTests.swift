import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct DeliveryPauseTests {
  private func pause(_ rig: DeliveryRig, seconds: TimeInterval) async {
    let until = rig.clock.now().addingTimeInterval(seconds)
    await rig.config.update { $0.pausedUntil = until }
  }

  private func unnotifiedCount(_ rig: DeliveryRig) async -> Int {
    await rig.history.unnotified(limit: 10, offset: 0).count
  }

  @Test func pausedMessagesAreStoredButNotPosted() async throws {
    let rig = DeliveryRig()
    await pause(rig, seconds: 600)
    try await rig.receive("a")
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    #expect(await unnotifiedCount(rig) == 1)
    await rig.service.shutdown()
  }

  @Test func theEndOfThePauseShowsWhatWasHeldBack() async throws {
    let rig = DeliveryRig()
    await pause(rig, seconds: 600)
    try await rig.receive("a")
    try await rig.receive("b")
    await rig.settle()
    await rig.advance(601)
    #expect(await rig.waitForPosts(1))
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    #expect(await rig.poster.postedIDs == ["a", "b"])
    #expect(await rig.eventually { await unnotifiedCount(rig) == 0 })
    await rig.service.shutdown()
  }

  @Test func clearingThePauseResumesAtTheNextReminderPoll() async throws {
    let rig = DeliveryRig()
    await pause(rig, seconds: 3600)
    try await rig.receive("a")
    await rig.settle()
    await rig.service.start()
    #expect(await rig.waitForSleepers(2))
    await rig.config.update { $0.pausedUntil = nil }
    await rig.advance(31)
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func aPauseOverButNothingHeldBackReconcilesNothing() async throws {
    let rig = DeliveryRig()
    await rig.service.start()
    await pause(rig, seconds: 10)
    await rig.advance(60)
    #expect(await rig.poster.attempts == 0)
    await rig.service.shutdown()
  }

  @Test func anExpiredPauseDoesNotHoldAnythingBack() async throws {
    let rig = DeliveryRig()
    await rig.config.update { $0.pausedUntil = rig.clock.now().addingTimeInterval(-1) }
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func aSummaryIsHeldBackToo() async throws {
    let rig = DeliveryRig()
    for index in 0..<3 {
      try await rig.history.append(rig.message("m\(index)", age: 3 * 3600 - Double(index)))
    }
    await pause(rig, seconds: 600)
    await rig.service.reconcile()
    await rig.settle()
    #expect(await rig.poster.summaries.isEmpty)
    #expect(await unnotifiedCount(rig) == 3)
    await rig.service.shutdown()
  }

  @Test func aLocalMessageIsDismissedAfterItsOwnTime() async throws {
    let rig = DeliveryRig()
    let message = rig.message("local-1", topic: "local")
    try await rig.history.append(message)
    await rig.service.deliverLocal(message, dismissAfter: 5)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.posted.first?.dismissAfter == .seconds(5))
    #expect(await rig.waitForSleepers(1))
    await rig.advance(6)
    #expect(await rig.poster.removed == ["local/local-1"])
    await rig.service.shutdown()
  }

  @Test func theDismissOverrideDoesNotLeakToOtherMessages() async throws {
    let rig = DeliveryRig()
    let local = rig.message("local-1", topic: "local")
    try await rig.history.append(local)
    await rig.service.deliverLocal(local, dismissAfter: 5)
    #expect(await rig.waitForPosts(1))
    await rig.settle()
    await rig.advance(2)
    try await rig.receive("other", topic: "local")
    #expect(await rig.waitForPosts(2))
    #expect(await rig.poster.posted.last?.dismissAfter == nil)
    await rig.service.shutdown()
  }
}
