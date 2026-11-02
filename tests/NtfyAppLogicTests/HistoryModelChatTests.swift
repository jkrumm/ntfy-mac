import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct HistoryModelConversationTests {
  @Test func conversationsAreOrderedByLatestActivityWithUnreadCounts() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 30)
    await rig.add("b1", topic: "builds", age: 10)
    await rig.add("a2", topic: "alerts", age: 20)
    await rig.add("c1", topic: "cron", age: 50)
    await rig.pipeline.history.markRead(topic: "cron", id: "c1")
    await rig.start()
    #expect(rig.model.conversations.map(\.topic) == ["builds", "alerts", "cron"])
    #expect(rig.model.conversations.map(\.unread) == [1, 2, 0])
    #expect(rig.model.conversation("alerts")?.preview == "body a2")
    #expect(rig.model.conversation("nope") == nil)
    rig.model.stop()
  }

  @Test func aNewMessageMovesItsConversationToTheTop() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 30)
    await rig.add("b1", topic: "builds", age: 10)
    await rig.start()
    #expect(rig.model.conversations.first?.topic == "builds")
    await rig.add("a2", topic: "alerts", age: 1)
    await rig.model.refresh()
    #expect(rig.model.conversations.map(\.topic) == ["alerts", "builds"])
    rig.model.stop()
  }

  @Test func theConversationListIgnoresTheTopicSelection() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 2)
    await rig.add("b1", topic: "builds", age: 1)
    await rig.start()
    rig.model.selectedTopic = "alerts"
    await rig.model.refresh()
    #expect(rig.model.conversations.count == 2)
    #expect(rig.model.thread.map(\.key.id) == ["a1"])
    rig.model.stop()
  }

  @Test func theUrgentMarkerNeedsAnUnacknowledgedHighMessage() async {
    let rig = HistoryModelRig()
    await rig.add("hot", topic: "alerts", age: 5, priority: .max)
    await rig.add("calm", topic: "builds", age: 4, priority: .default)
    await rig.add("done", topic: "cron", age: 3, priority: .high)
    await rig.pipeline.history.acknowledge(topic: "cron", id: "done")
    await rig.start()
    #expect(rig.model.conversation("alerts")?.hasUrgent == true)
    #expect(rig.model.conversation("builds")?.hasUrgent == false)
    #expect(rig.model.conversation("cron")?.hasUrgent == false)
    rig.model.stop()
  }

  @Test func theAvatarComesFromTheNewestMessagesTagsOrTheInitial() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 5, tags: ["warning"])
    await rig.add("a2", topic: "alerts", age: 4)
    await rig.add("b1", topic: "builds", age: 3)
    await rig.start()
    #expect(rig.model.conversation("alerts")?.avatar.glyph == TagEmoji.emoji(for: "warning"))
    #expect(rig.model.conversation("builds")?.avatar.glyph == "B")
    rig.model.stop()
  }

  @Test func theThreadIsChronologicalAndGroupedByDay() async {
    let rig = HistoryModelRig()
    await rig.add("old", age: 3 * 86_400)
    await rig.add("mid", age: 100)
    await rig.add("new", age: 10)
    await rig.start()
    #expect(rig.model.thread.map(\.key.id) == ["old", "mid", "new"])
    #expect(rig.model.days.count == 2)
    #expect(rig.model.days.last?.messages.map(\.key.id) == ["mid", "new"])
    rig.model.stop()
  }

  @Test func pagingExtendsTheThreadBackwardsOnly() async {
    let rig = HistoryModelRig(pageSize: 2)
    for index in 1...5 { await rig.add("m\(index)", age: Double(60 - index)) }
    await rig.start()
    #expect(rig.model.thread.map(\.key.id) == ["m4", "m5"])
    #expect(rig.model.hasMore)
    await rig.model.loadMore()
    #expect(rig.model.thread.map(\.key.id) == ["m2", "m3", "m4", "m5"])
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
}

@MainActor @Suite struct HistoryModelReadOnScrollTests {
  private func rig() async -> HistoryModelRig {
    let rig = HistoryModelRig()
    await rig.add("a", age: 3)
    await rig.add("b", age: 2)
    await rig.add("c", age: 1)
    await rig.start()
    return rig
  }

  private func key(_ id: String) -> MessageKey { MessageKey(topic: "alerts", id: id) }

  /// Waits until the debounce task sleeps, then lets the clock pass it.
  private func elapse(_ rig: HistoryModelRig) async {
    _ = await rig.eventually { rig.pipeline.clock.sleeperCount > 0 }
    rig.pipeline.clock.advance(by: .seconds(1))
  }

  @Test func visibleMessagesAreMarkedReadOnceTheThreadSettles() async {
    let rig = await rig()
    rig.model.messageAppeared(key("b"))
    rig.model.messageAppeared(key("c"))
    #expect(rig.model.thread.allSatisfy { !$0.detail.isRead })
    await elapse(rig)
    #expect(
      await rig.eventually {
        rig.model.thread.filter(\.detail.isRead).map(\.key.id) == ["b", "c"]
      })
    #expect(rig.model.conversation("alerts")?.unread == 1)
    rig.model.stop()
  }

  @Test func scrollingRestartsTheWaitSoNothingIsReadMidScroll() async {
    let rig = await rig()
    rig.model.messageAppeared(key("a"))
    _ = await rig.eventually { rig.pipeline.clock.sleeperCount == 1 }
    rig.pipeline.clock.advance(by: .milliseconds(400))
    rig.model.messageAppeared(key("b"))
    rig.pipeline.clock.advance(by: .milliseconds(400))
    for _ in 0..<2000 { await Task.yield() }
    #expect(rig.model.thread.allSatisfy { !$0.detail.isRead })
    await elapse(rig)
    #expect(await rig.eventually { rig.model.thread.filter(\.detail.isRead).count == 2 })
    rig.model.stop()
  }

  @Test func aMessageThatLeftTheScreenIsNotMarkedRead() async {
    let rig = await rig()
    rig.model.messageAppeared(key("a"))
    rig.model.messageAppeared(key("b"))
    rig.model.messageDisappeared(key("a"))
    await elapse(rig)
    #expect(await rig.eventually { rig.model.thread.filter(\.detail.isRead).count == 1 })
    #expect(rig.model.thread.first { $0.key.id == "a" }?.detail.isRead == false)
    rig.model.stop()
  }

  @Test func loadingTheThreadMarksNothingRead() async {
    let rig = await rig()
    rig.pipeline.clock.advance(by: .seconds(10))
    await rig.model.refresh()
    #expect(rig.model.thread.allSatisfy { !$0.detail.isRead })
    rig.model.stop()
  }
}

@MainActor @Suite struct HistoryModelComposerTests {
  private func rig(
    resolution: PublisherResolution? = nil
  ) async -> (HistoryModelRig, RecordingPublisher) {
    let rig = HistoryModelRig()
    await rig.add("a", topic: "alerts", age: 10)
    await rig.add("b", topic: "builds", age: 5)
    let publisher = RecordingPublisher(history: rig.pipeline.history, clock: rig.pipeline.clock)
    rig.model.publisher = StubPublisherProvider(resolution: resolution ?? .ready(publisher))
    await rig.start()
    return (rig, publisher)
  }

  @Test func theAllEntryDisablesTheComposerWithAnExplanation() async {
    let (rig, _) = await rig()
    #expect(rig.model.composerAvailability == .needsConversation)
    #expect(rig.model.composerAvailability.explanation != nil)
    rig.model.draft = "ignored"
    #expect(rig.model.draft.isEmpty)
    #expect(!rig.model.canSend)
    rig.model.selectedTopic = "alerts"
    #expect(rig.model.composerAvailability == .ready(topic: "alerts"))
    #expect(rig.model.composerAvailability.explanation == nil)
    rig.model.stop()
  }

  @Test func sendingNeedsTextThatIsNotBlank() async {
    let (rig, _) = await rig()
    rig.model.selectedTopic = "alerts"
    #expect(!rig.model.canSend)
    rig.model.draft = "  \n "
    #expect(!rig.model.canSend)
    rig.model.draft = "hello"
    #expect(rig.model.canSend)
    rig.model.stop()
  }

  @Test func aSentMessagePublishesTrimmedClearsTheDraftAndSitsOnTheRight() async {
    let (rig, publisher) = await rig()
    rig.model.selectedTopic = "alerts"
    rig.model.draft = "  deploy now \n"
    await rig.model.send()
    let requests = await publisher.requests
    #expect(requests == [PublishRequest(topic: "alerts", message: "deploy now")])
    #expect(requests.first?.priority == nil)
    #expect(rig.model.draft.isEmpty)
    #expect(rig.model.composerState == .idle)
    await rig.model.refresh()
    let sent = rig.model.thread.last
    #expect(sent?.key.id == "sent-1")
    #expect(sent?.isOwn == true)
    #expect(rig.model.thread.filter(\.isOwn).count == 1)
    #expect(rig.model.conversation("alerts")?.preview == "You: deploy now")
    rig.model.stop()
  }

  @Test func theChosenPriorityTravelsAndTheDefaultIsLeftToTheServer() async {
    let (rig, publisher) = await rig()
    rig.model.selectedTopic = "alerts"
    rig.model.composerPriority = .max
    rig.model.draft = "fire"
    await rig.model.send()
    rig.model.composerPriority = .default
    rig.model.draft = "calm"
    await rig.model.send()
    #expect(await publisher.requests.map(\.priority) == [.max, nil])
    rig.model.stop()
  }

  @Test func aSecondSendWhileOneRunsIsIgnored() async {
    let (rig, publisher) = await rig()
    rig.model.selectedTopic = "alerts"
    await publisher.hold()
    rig.model.draft = "once"
    let first = Task { await rig.model.send() }
    #expect(await rig.eventually { rig.model.composerState == .sending })
    #expect(!rig.model.canSend)
    await rig.model.send()
    await publisher.release()
    await first.value
    #expect(await publisher.requests.count == 1)
    #expect(rig.model.composerState == .idle)
    rig.model.stop()
  }

  @Test func eachConversationKeepsItsOwnDraft() async {
    let (rig, _) = await rig()
    rig.model.selectedTopic = "alerts"
    rig.model.draft = "for alerts"
    rig.model.selectedTopic = "builds"
    #expect(rig.model.draft.isEmpty)
    rig.model.draft = "for builds"
    rig.model.selectedTopic = "alerts"
    #expect(rig.model.draft == "for alerts")
    rig.model.stop()
  }

  @Test(arguments: [
    (NtfyError.unauthorized, "token"),
    (.serverUnreachable, "could not be reached"),
    (.rateLimited(retryAfter: 30), "30 seconds"),
    (.rateLimited(retryAfter: nil), "throttling"),
    (.redirected, "redirected"),
    (.insecureServer, "plain http"),
    (.invalidTopic("a b"), "a b"),
    (.invalidResponse("x"), "answer"),
    (.storage("disk"), "disk"),
  ])
  func aFailedSendKeepsTheDraftAndSaysWhy(error: NtfyError, fragment: String) async {
    let (rig, publisher) = await rig()
    rig.model.selectedTopic = "alerts"
    await publisher.fail(with: error)
    rig.model.draft = "keep me"
    await rig.model.send()
    guard case .failed(let text) = rig.model.composerState else {
      Issue.record("expected a failure, got \(rig.model.composerState)")
      return
    }
    #expect(text.contains(fragment))
    #expect(rig.model.draft == "keep me")
    #expect(rig.model.canSend)
    #expect(rig.model.thread.filter(\.isOwn).isEmpty)
    rig.model.stop()
  }

  @Test func editingOrSwitchingConversationClearsTheError() async {
    let (rig, publisher) = await rig()
    rig.model.selectedTopic = "alerts"
    await publisher.fail(with: .serverUnreachable)
    rig.model.draft = "x"
    await rig.model.send()
    rig.model.draft = "xy"
    #expect(rig.model.composerState == .idle)
    await rig.model.send()
    rig.model.selectedTopic = "builds"
    #expect(rig.model.composerState == .idle)
    rig.model.stop()
  }

  @Test func withoutAServerTheComposerSaysSoInsteadOfDoingNothing() async {
    let (rig, publisher) = await rig(resolution: .notConfigured)
    rig.model.selectedTopic = "alerts"
    rig.model.draft = "hi"
    await rig.model.send()
    #expect(rig.model.composerState == .failed(ComposerErrorText.notConfigured))
    #expect(rig.model.draft == "hi")
    #expect(await publisher.requests.isEmpty)
    rig.model.stop()
  }

  @Test func unusableSettingsShowTheirOwnReason() async {
    let (rig, _) = await rig(resolution: .invalid("Invalid NTFY URL: nope"))
    rig.model.selectedTopic = "alerts"
    rig.model.draft = "hi"
    await rig.model.send()
    #expect(rig.model.composerState == .failed("Invalid NTFY URL: nope"))
    rig.model.stop()
  }

  @Test func aProviderThatThrowsBecomesAMessageToo() async {
    let rig = HistoryModelRig()
    await rig.add("a", topic: "alerts")
    rig.model.publisher = FailingPublisherProvider(error: .storage("keychain locked"))
    await rig.start()
    rig.model.selectedTopic = "alerts"
    rig.model.draft = "hi"
    await rig.model.send()
    guard case .failed(let text) = rig.model.composerState else {
      Issue.record("expected a failure")
      return
    }
    #expect(text.contains("keychain locked"))
    rig.model.stop()
  }

  @Test func noPublisherWiredStillFailsLoudly() async {
    let rig = HistoryModelRig()
    await rig.add("a", topic: "alerts")
    await rig.start()
    rig.model.selectedTopic = "alerts"
    rig.model.draft = "hi"
    await rig.model.send()
    #expect(rig.model.composerState == .failed(ComposerErrorText.notConfigured))
    rig.model.stop()
  }
}
