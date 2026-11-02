import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct DeliveryTopicSettingsTests {
  private func rig(_ settings: [String: TopicSettings]) -> DeliveryRig {
    DeliveryRig(
      config: Config(
        dismiss: [1: 0, 2: 0, 3: 0, 4: 0, 5: 0], reAlert: false, topicSettings: settings))
  }

  private func unnotifiedCount(_ rig: DeliveryRig) async -> Int {
    await rig.history.unnotified(limit: 10, offset: 0).count
  }

  @Test func aMutedTopicIsStoredAndMarkedNotifiedWithoutAPost() async throws {
    let rig = rig(["noisy": TopicSettings(mute: true)])
    try await rig.receive("a", topic: "noisy", priority: 5)
    #expect(await rig.eventually { await unnotifiedCount(rig) == 0 })
    #expect(await rig.poster.attempts == 0)
    #expect(await rig.history.entries(HistoryQuery(limit: 10, offset: 0)).count == 1)
    await rig.service.shutdown()
  }

  @Test func otherTopicsAreUntouchedByAMute() async throws {
    let rig = rig(["noisy": TopicSettings(mute: true)])
    try await rig.receive("a", topic: "noisy")
    try await rig.receive("b", topic: "calm")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["b"])
    await rig.service.shutdown()
  }

  @Test func aMessageBelowTheMinimumPriorityIsSuppressedAndOneAtItIsShown() async throws {
    let rig = rig(["build": TopicSettings(minPriority: 4)])
    try await rig.receive("low", topic: "build", priority: 3)
    #expect(await rig.eventually { await unnotifiedCount(rig) == 0 })
    #expect(await rig.poster.attempts == 0)
    try await rig.receive("at", topic: "build", priority: 4)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["at"])
    await rig.service.shutdown()
  }

  @Test func aSuppressedMessageIsNeverShownByAReconcile() async throws {
    let rig = rig(["noisy": TopicSettings(mute: true)])
    try await rig.history.append(rig.message("a", topic: "noisy", age: 60))
    try await rig.history.append(rig.message("b", topic: "calm", age: 30))
    await rig.service.reconcile()
    #expect(await rig.waitForPosts(1))
    await rig.settle()
    #expect(await rig.poster.postedIDs == ["b"])
    #expect(await unnotifiedCount(rig) == 0)
    await rig.service.reconcile()
    await rig.settle()
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func suppressedMessagesDoNotCountInAMissedSummary() async throws {
    let rig = rig(["noisy": TopicSettings(mute: true)])
    for index in 0..<3 {
      try await rig.history.append(rig.message("n\(index)", topic: "noisy", age: 3 * 3600))
      try await rig.history.append(rig.message("c\(index)", topic: "calm", age: 3 * 3600 - 1))
    }
    await rig.service.reconcile()
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    #expect(await rig.poster.summaries.first?.count == 3)
    await rig.service.shutdown()
  }

  @Test func aMutedTopicStopsItsReAlerts() async throws {
    let config = Config(dismiss: [5: 0], reAlert: true, reAlertIntervalSeconds: 60)
    let rig = DeliveryRig(config: config)
    try await rig.receive("a", topic: "pager", priority: 5)
    #expect(await rig.waitForPosts(1))
    await rig.config.update { $0.topicSettings = ["pager": TopicSettings(mute: true)] }
    _ = await rig.waitForSleepers(1)
    await rig.advance(61)
    await rig.advance(61)
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func aMutedTopicDoesNotResumeItsReAlertsAtBoot() async throws {
    let config = Config(reAlert: true, topicSettings: ["pager": TopicSettings(mute: true)])
    let rig = DeliveryRig(config: config)
    try await rig.history.append(rig.message("a", topic: "pager", priority: 5, age: 60))
    await rig.service.reconcile()
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    #expect(rig.clock.sleeperCount == 0)
    await rig.service.shutdown()
  }

  @Test func aLocalMessageIgnoresTheTopicSettings() async throws {
    let rig = rig(["local": TopicSettings(mute: true)])
    let message = rig.message("l1", topic: "local", priority: 1)
    try await rig.history.append(message)
    await rig.service.deliverLocal(message, dismissAfter: nil)
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func theTopicEmojiReachesThePostedTitle() async throws {
    let rig = rig(["build": TopicSettings(emoji: "📦")])
    try await rig.receive("a", topic: "build")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.posted.first?.title == "📦 Build")
    await rig.service.shutdown()
  }

  @Test(arguments: ["", "a/b", "ünï cödé", "🔥", "with space", "quote\"back\\slash", "../x"])
  func oddTopicNamesWithSettingsDoNotCrash(topic: String) async throws {
    let rig = rig([topic: TopicSettings(minPriority: 4, emoji: "📦")])
    try await rig.receive("low", topic: topic, priority: 2)
    try await rig.receive("high", topic: topic, priority: 5)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["high"])
    #expect(await rig.poster.posted.first?.title.hasPrefix("📦 ") == true)
    await rig.service.shutdown()
  }
}
