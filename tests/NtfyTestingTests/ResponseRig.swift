import Foundation
import NtfyCore
import NtfyTesting

/// A response handler wired to recording fakes and an in-memory history.
struct ResponseRig {
  let clock = FakeClock()
  let history: InMemoryHistoryStore
  let config: InMemoryConfigStore
  let delivery = RecordingResponseDelivery()
  let opener: RecordingLinkOpener
  let presenter = RecordingHistoryPresenter()
  let confirmer: ScriptedActionConfirmer
  let runner: RecordingHTTPActionRunner
  let handler: ResponseHandler

  init(
    config initial: Config = Config(), openSucceeds: Bool = true, confirms: Bool = true,
    runnerFailure: NtfyError? = nil
  ) {
    history = InMemoryHistoryStore(clock: clock)
    config = InMemoryConfigStore(initial)
    opener = RecordingLinkOpener(succeeds: openSucceeds)
    confirmer = ScriptedActionConfirmer(answer: confirms)
    runner = RecordingHTTPActionRunner(failingWith: runnerFailure)
    handler = ResponseHandler(
      delivery: delivery, inbox: history, config: config, opener: opener, presenter: presenter,
      confirmer: confirmer, runner: runner)
  }

  /// Stores a message and returns its ref.
  @discardableResult
  func store(
    _ id: String = "1", click: URL? = nil, priority: Priority = .default,
    actions: [MessageAction] = []
  ) async throws -> MessageRef {
    let message = NtfyMessage(
      id: id, topic: "t", time: clock.now(), body: "body", priority: priority, click: click,
      actions: actions)
    try await history.append(message)
    return MessageRef(topic: "t", id: id)
  }

  @discardableResult
  func respond(_ ref: MessageRef, _ kind: NotificationResponse.Kind) async -> ResponseOutcome {
    await handler.handle(NotificationResponse(ref: ref, kind: kind))
  }
}

func httpAction(
  _ label: String = "Do it", url: String = "https://example.com/hook", clear: Bool = false
) -> MessageAction {
  MessageAction(kind: .http, label: label, url: URL(string: url), body: "go", clear: clear)
}
