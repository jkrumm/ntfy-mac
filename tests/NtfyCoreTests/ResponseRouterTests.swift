import Testing

@testable import NtfyCore

private actor Seen {
  private(set) var ids: [String] = []
  func add(_ response: NotificationResponse) { ids.append(response.ref.id) }
}

@Suite struct ResponseRouterTests {
  private func response(_ id: String) -> NotificationResponse {
    NotificationResponse(ref: MessageRef(topic: "t", id: id), kind: .body)
  }

  @Test func aHandlerReceivesResponsesDirectly() async {
    let router = ResponseRouter()
    let seen = Seen()
    await router.use { await seen.add($0) }
    await router.handle(response("a"))
    #expect(await seen.ids == ["a"])
  }

  @Test func responsesWithoutAHandlerWaitAndReplayInOrder() async {
    let router = ResponseRouter()
    let seen = Seen()
    await router.handle(response("a"))
    await router.handle(response("b"))
    #expect(await seen.ids.isEmpty)
    await router.use { await seen.add($0) }
    #expect(await seen.ids == ["a", "b"])
    await router.handle(response("c"))
    #expect(await seen.ids == ["a", "b", "c"])
  }

  @Test func theBufferKeepsTheNewestResponses() async {
    let router = ResponseRouter()
    let seen = Seen()
    for index in 0..<(ResponseRouter.capacity + 3) { await router.handle(response("\(index)")) }
    await router.use { await seen.add($0) }
    let ids = await seen.ids
    #expect(ids.count == ResponseRouter.capacity)
    #expect(ids.first == "3")
    #expect(ids.last == "\(ResponseRouter.capacity + 2)")
  }

  @Test func removingTheHandlerBuffersAgain() async {
    let router = ResponseRouter()
    let seen = Seen()
    await router.use { await seen.add($0) }
    await router.use(nil)
    await router.handle(response("a"))
    #expect(await seen.ids.isEmpty)
    await router.use { await seen.add($0) }
    #expect(await seen.ids == ["a"])
  }
}
