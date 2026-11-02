import Foundation
import NtfyCore
import Synchronization
import Testing

@testable import NtfyClient

@Suite struct NtfyPollerTests {
  private static func line(_ id: String) -> String {
    #"{"id":"\#(id)","time":1,"event":"message","topic":"t","message":"m"}"#
  }

  private func poll(
    _ stub: Stub, token: String? = "tk", base: URL? = nil, since: String? = "abc",
    diagnostics: @escaping @Sendable (String) -> Void = { _ in }
  ) async -> (result: Result<[NtfyMessage], NtfyError>, base: URL) {
    let base = base ?? StubURLProtocol.register(stub)
    let poller = NtfyPoller(
      base: base, token: token, session: StubURLProtocol.session(), diagnostics: diagnostics)
    do {
      return (.success(try await poller.poll(topics: ["t"], since: since)), base)
    } catch {
      return (.failure(error), base)
    }
  }

  @Test func returnsOnlyMessagesAndSendsPollRequest() async throws {
    let lines = [
      #"{"id":"o","time":1,"event":"open","topic":"t"}"#, Self.line("1"),
      #"{"id":"k","time":1,"event":"keepalive","topic":"t"}"#, Self.line("2"),
    ]
    let (result, base) = await poll(Stub(lines: lines))
    #expect(try result.get().map(\.id) == ["1", "2"])
    let request = try #require(StubURLProtocol.requests(for: base).first)
    #expect(request.url?.path == "/t/json")
    #expect(request.url?.query == "since=abc&poll=1")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tk")
  }

  @Test func emptyCacheIsAnEmptyList() async throws {
    #expect(try await poll(Stub()).result.get().isEmpty)
  }

  @Test func badLinesAreSkippedAndReported() async throws {
    let skipped = Mutex(0)
    let stub = Stub(lines: [Self.line("1"), "garbage", Self.line("2")])
    let (result, _) = await poll(stub) { _ in skipped.withLock { $0 += 1 } }
    #expect(try result.get().map(\.id) == ["1", "2"])
    #expect(skipped.withLock { $0 } == 1)
  }

  @Test func pollDecodesActionsAttachmentAndIcon() async throws {
    let json =
      #"{"id":"1","time":1,"event":"message","topic":"t","icon":"https://e.com/i.png","#
      + #""attachment":{"name":"a.png","url":"https://e.com/a.png","type":"image/png"},"#
      + #""actions":[{"action":"view","label":"Open","url":"https://e.com"}]}"#
    let message = try #require(try await poll(Stub(lines: [json])).result.get().first)
    #expect(message.icon == URL(string: "https://e.com/i.png"))
    #expect(message.attachment?.mimeType == "image/png")
    #expect(message.actions.map(\.label) == ["Open"])
  }

  @Test func truncatedReplayIsReported() async throws {
    let notes = Mutex<[String]>([])
    let stub = Stub(
      headers: ["Content-Type": "application/x-ndjson", "X-Messages-Truncated": "1"],
      lines: [Self.line("1")])
    let (result, _) = await poll(stub) { note in notes.withLock { $0.append(note) } }
    #expect(try result.get().map(\.id) == ["1"])
    #expect(notes.withLock { $0 }.count == 1)
  }

  @Test(arguments: [(401, NtfyError.unauthorized), (403, .unauthorized), (503, .serverUnreachable)])
  func statusMapping(status: Int, expected: NtfyError) async {
    #expect(await poll(Stub(status: status)).result == .failure(expected))
  }

  @Test func rateLimitCarriesRetryAfter() async {
    let stub = Stub(status: 429, headers: ["Retry-After": "12"])
    #expect(await poll(stub).result == .failure(.rateLimited(retryAfter: 12)))
  }

  @Test func otherClientErrorsAreInvalidResponses() async {
    #expect(await poll(Stub(status: 404)).result == .failure(.invalidResponse("HTTP 404")))
  }

  @Test func redirectsAreRefused() async {
    let target = StubURLProtocol.register(Stub(lines: [Self.line("evil")]))
    #expect(await poll(Stub(redirectTo: target)).result == .failure(.redirected))
    #expect(StubURLProtocol.requests(for: target).isEmpty)
  }

  @Test func foreignResponseOriginIsTerminal() async {
    let other = URL(string: "https://elsewhere.test")!
    let result = await poll(Stub(lines: [Self.line("1")], respondFrom: other)).result
    #expect(result == .failure(.redirected))
  }

  @Test func plainHttpWithTokenIsRefusedBeforeAnyRequest() async {
    let base = StubURLProtocol.register(Stub(lines: [Self.line("1")]), scheme: "http")
    #expect(await poll(Stub(), base: base).result == .failure(.insecureServer))
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func loopbackHttpIsAllowedWithToken() async throws {
    let base = StubURLProtocol.register(
      Stub(lines: [Self.line("1")]), scheme: "http", host: "127.0.0.1")
    #expect(try await poll(Stub(), base: base).result.get().map(\.id) == ["1"])
  }

  @Test func invalidTopicsFailBeforeAnyRequest() async {
    let base = StubURLProtocol.register(Stub())
    let poller = NtfyPoller(base: base, token: nil, session: StubURLProtocol.session())
    await #expect(throws: NtfyError.invalidTopic("bad topic")) {
      try await poller.poll(topics: ["bad topic"], since: nil)
    }
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func unreachableServerIsReported() async throws {
    let unregistered = try #require(URL(string: "https://nobody-\(UUID().uuidString).test"))
    let result = await poll(Stub(), base: unregistered).result
    #expect(result == .failure(.serverUnreachable))
  }
}

@Suite struct NtfyAccountClientTests {
  private func topics(
    _ stub: Stub, token: String = "tk", base: URL? = nil
  ) async -> (result: Result<[String], NtfyError>, base: URL) {
    let base = base ?? StubURLProtocol.register(stub)
    let client = NtfyAccountClient(base: base, token: token, session: StubURLProtocol.session())
    do {
      return (.success(try await client.subscribedTopics()), base)
    } catch {
      return (.failure(error), base)
    }
  }

  private func json(_ body: String) -> Stub {
    Stub(headers: ["Content-Type": "application/json"], lines: [body])
  }

  @Test func returnsSubscribedTopicsWithBearerToken() async throws {
    let body = """
      {"username":"u","subscriptions":[\
      {"topic":"a"},\
      {"topic":"b","display_name":"B"}]}
      """
    let (result, base) = await topics(json(body))
    #expect(try result.get() == ["a", "b"])
    let request = try #require(StubURLProtocol.requests(for: base).first)
    #expect(request.url?.path == "/v1/account")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tk")
  }

  @Test func duplicateTopicsAreCollapsed() async throws {
    let body = """
      {"subscriptions":[{"topic":"x"},{"topic":"x"}]}
      """
    #expect(try await topics(json(body)).result.get() == ["x"])
  }

  @Test(arguments: [#"{"username":"u"}"#, #"{"subscriptions":[]}"#, #"{"subscriptions":null}"#])
  func missingOrEmptySubscriptionsAreEmpty(body: String) async throws {
    #expect(try await topics(json(body)).result.get().isEmpty)
  }

  @Test func undecodableBodyIsInvalid() async {
    let result = await topics(json("not json")).result
    #expect(result == .failure(.invalidResponse("undecodable account response")))
  }

  @Test(arguments: [(401, NtfyError.unauthorized), (403, .unauthorized), (502, .serverUnreachable)])
  func statusMapping(status: Int, expected: NtfyError) async {
    #expect(await topics(Stub(status: status)).result == .failure(expected))
  }

  @Test func rateLimitCarriesRetryAfter() async {
    let stub = Stub(status: 429, headers: ["Retry-After": "9"])
    #expect(await topics(stub).result == .failure(.rateLimited(retryAfter: 9)))
  }

  @Test func redirectsAreRefused() async {
    let target = StubURLProtocol.register(json(#"{"subscriptions":[]}"#))
    #expect(await topics(Stub(redirectTo: target)).result == .failure(.redirected))
    #expect(StubURLProtocol.requests(for: target).isEmpty)
  }

  @Test func plainHttpWithTokenIsRefusedBeforeAnyRequest() async {
    let base = StubURLProtocol.register(json(#"{"subscriptions":[]}"#), scheme: "http")
    #expect(await topics(Stub(), base: base).result == .failure(.insecureServer))
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func loopbackHttpIsAllowedWithToken() async throws {
    let base = StubURLProtocol.register(
      json(#"{"subscriptions":[{"topic":"a"}]}"#), scheme: "http", host: "::1")
    #expect(try await topics(Stub(), base: base).result.get() == ["a"])
  }

  @Test func keepsTheBasePath() async throws {
    let plain = StubURLProtocol.register(json(#"{}"#))
    let base = try #require(URL(string: plain.absoluteString + "/ntfy"))
    _ = await topics(Stub(), base: base)
    #expect(StubURLProtocol.requests(for: plain).first?.url?.path == "/ntfy/v1/account")
  }
}
