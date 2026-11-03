import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

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

  @Test func theComposerTargetsTheSelectedTopicElseTheNewest() async {
    let (rig, _) = await rig()
    #expect(rig.model.composerAvailability == .ready(topic: "builds"))
    rig.model.selectedTopic = "alerts"
    rig.model.openComposer()
    #expect(rig.model.composerAvailability == .ready(topic: "alerts"))
    #expect(rig.model.composerAvailability.explanation == nil)
    rig.model.composerTopic = "builds"
    #expect(rig.model.composerAvailability == .ready(topic: "builds"))
    rig.model.stop()
  }

  @Test func openingTheComposerResetsPriorityAndErrorButKeepsTheDraft() async {
    let (rig, publisher) = await rig()
    await publisher.fail(with: .serverUnreachable)
    rig.model.composerPriority = .max
    rig.model.draft = "half written"
    await rig.model.send()
    #expect(rig.model.composerState != .idle)
    rig.model.openComposer()
    #expect(rig.model.composerPriority == .default)
    #expect(rig.model.composerState == .idle)
    #expect(rig.model.draft == "half written")
    rig.model.stop()
  }

  @Test func subscribedTopicsWithoutMessagesCanBeTargeted() async {
    let pipeline = PipelineFixture(config: Config(extraTopics: ["zeta", "alerts", "alpha"]))
    let rig = HistoryModelRig(pipeline: pipeline)
    await rig.add("a", topic: "alerts")
    await rig.start()
    #expect(rig.model.composerTopics == ["alerts", "alpha", "zeta"])
    rig.model.stop()
  }

  @Test func withoutAnyTopicTheComposerExplainsItself() async {
    let rig = HistoryModelRig()
    await rig.start()
    #expect(rig.model.composerAvailability == .noTopic)
    #expect(rig.model.composerAvailability.explanation != nil)
    rig.model.draft = "text"
    #expect(!rig.model.canSend)
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

  @Test func aSentMessagePublishesTrimmedClearsTheDraftAnd() async {
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
    #expect(rig.model.rows.first?.key.id == "sent-1")
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

  @Test func textTypedWhileTheSendRunsSurvivesItsSuccess() async {
    let (rig, publisher) = await rig()
    rig.model.selectedTopic = "alerts"
    await publisher.hold()
    rig.model.draft = "first"
    let sending = Task { await rig.model.send() }
    #expect(await rig.eventually { rig.model.composerState == .sending })
    rig.model.draft = "first and more"
    await publisher.release()
    await sending.value
    #expect(rig.model.draft == "first and more")
    #expect(rig.model.composerState == .idle)
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
    #expect(rig.model.rows.map(\.key.id).allSatisfy { !$0.hasPrefix("sent") })
    rig.model.stop()
  }

  @Test func editingOrSwitchingTheTopicClearsTheError() async {
    let (rig, publisher) = await rig()
    rig.model.selectedTopic = "alerts"
    await publisher.fail(with: .serverUnreachable)
    rig.model.draft = "x"
    await rig.model.send()
    rig.model.draft = "xy"
    #expect(rig.model.composerState == .idle)
    await rig.model.send()
    rig.model.composerTopic = "builds"
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
