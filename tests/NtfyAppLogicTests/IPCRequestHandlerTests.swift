import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyIPC
import NtfyTesting
import Testing

@Suite struct IPCRequestHandlerTests {
  @Test func notifyPostsWithoutAnyConfiguration() async throws {
    let rig = HandlerRig()
    let response = await rig.notify(NotifyPayload(title: "Hi", body: "Deploy done", priority: 4))

    #expect(response.status == .success)
    #expect(response.result?.notify?.posted == true)
    #expect(await rig.waitForPosts(1))
    let posted = try #require(await rig.poster.posted.first)
    #expect(posted.messageRef.topic == IPCRequestHandler.localTopic)
    #expect(await rig.history.recent(limit: 5).count == 1)
  }

  @Test func deniedPermissionIsPermissionDenied() async {
    let rig = HandlerRig(permission: NotificationPermission(authorization: .denied))
    let response = await rig.notify(NotifyPayload(body: "x"))

    #expect(response.code == .permissionDenied)
    #expect(await rig.poster.attempts == 0)
  }

  @Test func pausedNotifyIsStoredButNotPosted() async {
    var config = Config()
    config.pausedUntil = FakeClock().now().addingTimeInterval(3600)
    let rig = HandlerRig(config: config)
    let response = await rig.notify(NotifyPayload(body: "x"))

    #expect(response.status == .success)
    #expect(response.result?.notify?.posted == false)
    #expect(await rig.history.recent(limit: 5).count == 1)
    #expect(await rig.poster.attempts == 0)
  }

  @Test func missingOrEmptyBodyIsBadRequest() async {
    let rig = HandlerRig()
    #expect(await rig.send(Request(id: "1", command: .notify)).code == .badRequest)
    #expect(await rig.notify(NotifyPayload(body: "")).code == .badRequest)
    #expect(await rig.poster.attempts == 0)
  }

  @Test func ackOfUnknownMessageIsNotFound() async {
    let rig = HandlerRig()
    let response = await rig.send(
      Request(id: "1", command: .ack, ack: MessageTarget(topic: "local", id: "nope")))
    #expect(response.code == .notFound)
  }

  @Test func ackRemindAndAckAllWorkOnLocalMessages() async {
    let rig = HandlerRig()
    _ = await rig.notify(NotifyPayload(body: "one", priority: 5))
    _ = await rig.notify(NotifyPayload(body: "two", priority: 5))
    let stored = await rig.history.recent(limit: 5)
    #expect(stored.count == 2)
    let first = stored[0]

    let remind = await rig.send(
      Request(
        id: "2", command: .remind,
        remind: RemindPayload(topic: first.topic, id: first.id, until: Date.distantFuture)))
    #expect(remind.status == .success)

    let ack = await rig.send(
      Request(id: "3", command: .ack, ack: MessageTarget(topic: first.topic, id: first.id)))
    #expect(ack.status == .success)

    let all = await rig.send(Request(id: "4", command: .ackAll, ackAll: AckAllPayload(topic: nil)))
    #expect(all.result?.ackAll?.acknowledged == 1)
  }

  @Test func noPipelineIsAppUnavailable() async {
    let rig = HandlerRig(pipelineAvailable: false)
    #expect(await rig.notify(NotifyPayload(body: "x")).code == .appUnavailable)
    let ack = await rig.send(
      Request(id: "1", command: .ack, ack: MessageTarget(topic: "local", id: "x")))
    #expect(ack.code == .appUnavailable)
  }

  @Test func reconnectNeedsAStream() async {
    let rig = HandlerRig()
    #expect(await rig.send(Request(id: "1", command: .reconnect)).code == .appUnavailable)
  }

  @Test func statusWorksWithoutAStream() async throws {
    let rig = HandlerRig()
    let response = await rig.send(Request(id: "1", command: .status))
    #expect(response.result?.status?.connection == "stopped")
  }
}

@Suite struct NotifyValidationTests {
  private func code(_ payload: NotifyPayload) async -> ErrorCode? {
    await HandlerRig().notify(payload).code
  }

  @Test func clickURLMustPassTheURLPolicy() async {
    let bad = URL(string: "file:///etc/passwd")
    #expect(await code(NotifyPayload(body: "x", clickURL: bad)) == .badRequest)
    let javascript = URL(string: "javascript:alert(1)")
    #expect(await code(NotifyPayload(body: "x", clickURL: javascript)) == .badRequest)
    let fine = URL(string: "https://example.com/a")
    #expect(await code(NotifyPayload(body: "x", clickURL: fine)) == nil)
  }

  @Test func lengthsAreCapped() async {
    #expect(
      await code(NotifyPayload(title: String(repeating: "a", count: 257), body: "x")) == .badRequest
    )
    #expect(await code(NotifyPayload(title: String(repeating: "a", count: 256), body: "x")) == nil)
    #expect(await code(NotifyPayload(body: String(repeating: "a", count: 4097))) == .badRequest)
    #expect(await code(NotifyPayload(body: String(repeating: "a", count: 4096))) == nil)
    let manyTags = Array(repeating: "t", count: 17)
    #expect(await code(NotifyPayload(body: "x", tags: manyTags)) == .badRequest)
    let longTag = [String(repeating: "t", count: 65)]
    #expect(await code(NotifyPayload(body: "x", tags: longTag)) == .badRequest)
    #expect(await code(NotifyPayload(body: "x", tags: Array(repeating: "t", count: 16))) == nil)
  }

  @Test func dismissIsClampedAndMustBeFinite() async {
    #expect(await code(NotifyPayload(body: "x", dismissAfterSeconds: .nan)) == .badRequest)
    #expect(await code(NotifyPayload(body: "x", dismissAfterSeconds: .infinity)) == .badRequest)
    #expect(await code(NotifyPayload(body: "x", dismissAfterSeconds: -5)) == nil)
    #expect(await code(NotifyPayload(body: "x", dismissAfterSeconds: 1e9)) == nil)
  }
}
