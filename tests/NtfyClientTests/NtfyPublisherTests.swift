import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct NtfyPublisherTests {
  private static let json = ["Content-Type": "application/json"]
  private let request = PublishRequest(
    topic: "builds", message: "done", title: "CI", priority: Priority(clamping: 4),
    tags: ["ok"], click: URL(string: "https://example.com/1"))

  private func publisher(
    _ stub: Stub, scheme: String = "https", host: String? = nil, token: String = "tk_secret",
    allowInsecure: Bool = false, timeout: TimeInterval = 5
  ) -> (NtfyPublisher, URL) {
    let base = StubURLProtocol.register(stub, scheme: scheme, host: host)
    return (
      NtfyPublisher(
        base: base, token: token, allowInsecure: allowInsecure, timeout: timeout,
        session: StubURLProtocol.session()), base
    )
  }

  @Test func postsJSONWithTheBearerTokenAndReturnsTheIdAndTime() async throws {
    let reply = #"{"id":"abc123","time":1700000000,"event":"message","topic":"builds"}"#
    let (publisher, base) = publisher(Stub(headers: Self.json, lines: [reply]))
    let sent = try await publisher.publish(request)
    #expect(sent.id == "abc123")
    #expect(sent.topic == "builds")
    #expect(sent.time == Date(timeIntervalSince1970: 1_700_000_000))
    let recorded = try #require(StubURLProtocol.requests(for: base).first)
    #expect(recorded.httpMethod == "POST")
    #expect(recorded.value(forHTTPHeaderField: "Authorization") == "Bearer tk_secret")
    #expect(recorded.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try #require(recorded.httpBody ?? recorded.bodyStreamData())
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["topic"] as? String == "builds")
    #expect(object["message"] as? String == "done")
    #expect(object["title"] as? String == "CI")
    #expect(object["priority"] as? Int == 4)
    #expect(object["tags"] as? [String] == ["ok"])
    #expect(object["click"] as? String == "https://example.com/1")
  }

  @Test(arguments: [401, 403])
  func rejectedCredentialsAreUnauthorized(status: Int) async {
    let (publisher, _) = publisher(Stub(status: status, headers: Self.json, lines: ["{}"]))
    await #expect(throws: NtfyError.unauthorized) { try await publisher.publish(request) }
  }

  @Test func throttlingIsRateLimitedWithRetryAfter() async {
    let stub = Stub(status: 429, headers: Self.json.merging(["Retry-After": "7"]) { $1 }, lines: [])
    let (publisher, _) = publisher(stub)
    await #expect(throws: NtfyError.rateLimited(retryAfter: 7)) {
      try await publisher.publish(request)
    }
  }

  @Test func anUnreachableServerIsServerUnreachable() async throws {
    let base = try #require(URL(string: "https://unregistered-\(UUID().uuidString).test"))
    let publisher = NtfyPublisher(base: base, token: "tk", session: StubURLProtocol.session())
    await #expect(throws: NtfyError.serverUnreachable) { try await publisher.publish(request) }
  }

  @Test func serverErrorsAreServerUnreachable() async {
    let (publisher, _) = publisher(Stub(status: 503, headers: Self.json, lines: []))
    await #expect(throws: NtfyError.serverUnreachable) { try await publisher.publish(request) }
  }

  @Test func plainHTTPWithATokenIsRefusedBeforeAnythingIsSent() async {
    let (publisher, base) = publisher(
      Stub(headers: Self.json, lines: ["{}"]), scheme: "http", host: "ntfy.insecure.test")
    await #expect(throws: NtfyError.insecureServer) { try await publisher.publish(request) }
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func allowInsecureLiftsTheRefusal() async throws {
    let reply = #"{"id":"i1","time":1700000000,"topic":"builds"}"#
    let (publisher, _) = publisher(
      Stub(headers: Self.json, lines: [reply]), scheme: "http", host: "ntfy.optin.test",
      allowInsecure: true)
    #expect(try await publisher.publish(request).id == "i1")
  }

  @Test func redirectsAreNotFollowed() async throws {
    let target = try #require(URL(string: "https://elsewhere.test/"))
    // Generous timeout: a loaded hosted runner stalls the whole parallel run for 7-10 s.
    let (publisher, _) = publisher(Stub(redirectTo: target), timeout: 60)
    await #expect(throws: NtfyError.redirected) { try await publisher.publish(request) }
    #expect(StubURLProtocol.requests(for: target).isEmpty)
  }

  @Test func anInvalidTopicIsRejectedLocally() async {
    let (publisher, base) = publisher(Stub(headers: Self.json, lines: ["{}"]))
    let bad = PublishRequest(topic: "a/b", message: "x")
    await #expect(throws: NtfyError.invalidTopic("a/b")) { try await publisher.publish(bad) }
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func anUndecodableAnswerIsInvalidResponse() async {
    let (publisher, _) = publisher(Stub(headers: Self.json, lines: ["not json"]))
    await #expect(throws: NtfyError.invalidResponse("undecodable publish response")) {
      try await publisher.publish(request)
    }
  }
}

extension URLRequest {
  /// URLProtocol delivers a request body as a stream; reads it whole.
  fileprivate func bodyStreamData() -> Data? {
    guard let stream = httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
