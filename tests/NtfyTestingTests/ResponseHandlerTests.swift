import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct ResponseHandlerTests {
  private let link = URL(string: "https://example.com/page")!

  // MARK: Body

  @Test func bodyWithURLOpensItAndMarksOpened() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store(click: link)
    #expect(await rig.respond(ref, .body) == .completed)
    #expect(await rig.opener.opened == [link])
    #expect(await rig.presenter.shown.isEmpty)
    #expect(await rig.delivery.opened == [ref])
  }

  @Test func bodyWithoutURLShowsHistory() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store()
    #expect(await rig.respond(ref, .body) == .completed)
    #expect(await rig.presenter.shown == [ref])
    #expect(await rig.opener.opened.isEmpty)
    #expect(await rig.delivery.opened == [ref])
  }

  @Test func bodyFallsBackToHistoryWhenTheLinkCannotBeOpened() async throws {
    let rig = ResponseRig(openSucceeds: false)
    let ref = try await rig.store(click: link)
    await rig.respond(ref, .body)
    #expect(await rig.presenter.shown == [ref])
    #expect(await rig.delivery.opened == [ref])
  }

  @Test func disallowedSchemeInTheStoredMessageIsNeverOpened() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store(click: URL(string: "file:///etc/passwd"))
    await rig.respond(ref, .body)
    #expect(await rig.opener.opened.isEmpty)
    #expect(await rig.presenter.shown == [ref])
  }

  @Test func dismissedDoesNothing() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store(click: link)
    #expect(await rig.respond(ref, .dismissed) == .ignored("dismissed"))
    #expect(await rig.opener.opened.isEmpty)
    #expect(await rig.delivery.opened.isEmpty)
    #expect(await rig.delivery.acknowledged.isEmpty)
  }

  // MARK: Tampered ids

  @Test func unknownMessageIsALoggedNoOp() async {
    let rig = ResponseRig()
    let ref = MessageRef(topic: "t", id: "forged")
    for kind in [NotificationResponse.Kind.body, .button(id: "acknowledge")] {
      guard case .ignored = await rig.respond(ref, kind) else {
        Issue.record("expected the response to be ignored")
        return
      }
    }
    #expect(await rig.delivery.opened.isEmpty)
    #expect(await rig.delivery.acknowledged.isEmpty)
    #expect(await rig.presenter.shown.isEmpty)
  }

  @Test func unknownButtonIsANoOp() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store(actions: [httpAction()])
    guard case .ignored = await rig.respond(ref, .button(id: "http-nope")) else {
      Issue.record("expected the response to be ignored")
      return
    }
    #expect(await rig.runner.calls.isEmpty)
  }

  @Test func acknowledgeButtonOfAMessageWithoutReAlertIsUnknown() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store(priority: .default)
    guard case .ignored = await rig.respond(ref, .button(id: "acknowledge")) else {
      Issue.record("expected the response to be ignored")
      return
    }
    #expect(await rig.delivery.acknowledged.isEmpty)
  }

  // MARK: Buttons

  @Test func acknowledgeButtonAcknowledges() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store(priority: .max)
    #expect(await rig.respond(ref, .button(id: "acknowledge")) == .completed)
    #expect(await rig.delivery.acknowledged == [ref])
  }

  @Test func viewButtonOpensAndMarksRead() async throws {
    let rig = ResponseRig()
    let view = MessageAction(kind: .view, label: "Open", url: link)
    let ref = try await rig.store(actions: [view])
    #expect(await rig.respond(ref, .button(id: "view-open")) == .completed)
    #expect(await rig.opener.opened == [link])
    #expect(await rig.delivery.opened == [ref])
  }

  @Test func viewButtonThatCannotOpenDoesNotMarkRead() async throws {
    let rig = ResponseRig(openSucceeds: false)
    let view = MessageAction(kind: .view, label: "Open", url: link)
    let ref = try await rig.store(actions: [view])
    guard case .failed = await rig.respond(ref, .button(id: "view-open")) else {
      Issue.record("expected a failure")
      return
    }
    #expect(await rig.delivery.opened.isEmpty)
  }

  @Test func httpButtonWithoutConfirmationRunsAtOnce() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store(actions: [httpAction()])
    #expect(await rig.respond(ref, .button(id: "http-do-it")) == .completed)
    let calls = await rig.runner.calls
    #expect(calls.map(\.url.absoluteString) == ["https://example.com/hook"])
    #expect(calls.first?.method == "POST")
    #expect(calls.first?.body == "go")
    #expect(await rig.confirmer.asked.isEmpty)
    #expect(await rig.delivery.acknowledged.isEmpty)
  }

  @Test func declinedConfirmationSendsNothing() async throws {
    let rig = ResponseRig(confirms: false)
    let ref = try await rig.store(actions: [httpAction(url: "http://192.168.1.5/x")])
    #expect(await rig.respond(ref, .button(id: "http-do-it")) == .declined)
    #expect(await rig.runner.calls.isEmpty)
    #expect(await rig.confirmer.asked.count == 1)
    #expect(await rig.confirmer.asked.first?.label == "Do it")
  }

  @Test func acceptedConfirmationRuns() async throws {
    let rig = ResponseRig(confirms: true)
    let ref = try await rig.store(actions: [httpAction(url: "http://192.168.1.5/x")])
    #expect(await rig.respond(ref, .button(id: "http-do-it")) == .completed)
    #expect(await rig.confirmer.asked.count == 1)
    #expect(await rig.runner.calls.count == 1)
  }

  @Test func runnerFailureIsReportedNotThrown() async throws {
    let rig = ResponseRig(runnerFailure: .serverUnreachable)
    let ref = try await rig.store(actions: [httpAction(clear: true)])
    #expect(await rig.respond(ref, .button(id: "http-do-it")) == .failed(.serverUnreachable))
    #expect(await rig.delivery.acknowledged.isEmpty)
  }

  @Test func clearFlagAcknowledgesAfterSuccess() async throws {
    let rig = ResponseRig()
    let ref = try await rig.store(actions: [httpAction(clear: true)])
    #expect(await rig.respond(ref, .button(id: "http-do-it")) == .completed)
    #expect(await rig.delivery.acknowledged == [ref])
  }

  @Test func actionDeniedByTheCurrentConfigNeverRuns() async throws {
    let rig = ResponseRig()
    // Stored with a scheme the policy no longer treats as http: the button is gone and nothing runs.
    let ref = try await rig.store(actions: [httpAction(url: "https:///nohost")])
    guard case .ignored = await rig.respond(ref, .button(id: "http-do-it")) else {
      Issue.record("expected the response to be ignored")
      return
    }
    #expect(await rig.runner.calls.isEmpty)
  }

  @Test func privateTargetOptInChangeIsHonouredAtExecutionTime() async throws {
    let rig = ResponseRig(confirms: false)
    let ref = try await rig.store(actions: [httpAction(url: "http://192.168.1.5/x")])
    await rig.config.save(Config(allowPrivateNetworkActions: true))
    #expect(await rig.respond(ref, .button(id: "http-do-it")) == .completed)
    #expect(await rig.confirmer.asked.isEmpty)
    #expect(await rig.runner.calls.count == 1)
  }
}
