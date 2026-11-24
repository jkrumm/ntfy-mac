import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct AnthropicSummarizerTests {
  private let json = ["Content-Type": "application/json"]
  private let entries = [
    DigestEntry(
      topic: "ci", priority: 5, time: Date(timeIntervalSince1970: 1_700_000_000), title: "Red",
      body: "main is red")
  ]

  private func reply(_ text: String) -> Stub {
    Stub(
      headers: json, lines: [#"{"type":"message","content":[{"type":"text","text":"\#(text)"}]}"#])
  }

  private func summarizer(
    _ base: URL, key: String = "sk-test", model: String = "claude-haiku-5-5",
    allowInsecure: Bool = false, timeout: TimeInterval = 30
  ) -> AnthropicSummarizer {
    AnthropicSummarizer(
      endpoint: base, apiKey: key, model: model, allowInsecure: allowInsecure, timeout: timeout,
      session: StubURLProtocol.session())
  }

  private func body(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody ?? request.bodyStreamData())
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func theRequestHasTheDocumentedShape() async throws {
    let base = StubURLProtocol.register(reply("All quiet."))
    let text = try await summarizer(base).summarize(entries)
    #expect(text == "All quiet.")
    let sent = try #require(StubURLProtocol.requests(for: base).first)
    #expect(sent.httpMethod == "POST")
    #expect(sent.url?.path == "/v1/messages")
    #expect(sent.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
    let payload = try body(sent)
    #expect(payload["model"] as? String == "claude-haiku-5-5")
    #expect(payload["max_tokens"] as? Int == AnthropicSummarizer.maxTokens)
    #expect(payload["system"] as? String == SummaryPrompt.system)
    #expect((payload["thinking"] as? [String: String]) == ["type": "disabled"])
    let messages = try #require(payload["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    #expect(messages.first?["role"] as? String == "user")
    let content = try #require(messages.first?["content"] as? String)
    #expect(content.contains("topic=ci priority=5 unacknowledged Red: main is red"))
  }

  @Test func aGatewayPrefixIsKeptAndTheModelIsWhatWasConfigured() async throws {
    let root = StubURLProtocol.register(reply("ok"))
    let base = try #require(URL(string: root.absoluteString + "/anthropic"))
    _ = try await summarizer(base, key: "door-token", model: "haiku").summarize(entries)
    let sent = try #require(StubURLProtocol.requests(for: root).first)
    #expect(sent.url?.path == "/anthropic/v1/messages")
    #expect(sent.value(forHTTPHeaderField: "x-api-key") == "door-token")
    #expect(try body(sent)["model"] as? String == "haiku")
  }

  @Test(arguments: ["haiku", "claude-haiku-5-5", "Haiku"]) func aHaikuIsToldNotToThink(
    model: String
  ) async throws {
    let base = StubURLProtocol.register(reply("ok"))
    _ = try await summarizer(base, model: model).summarize(entries)
    let sent = try #require(StubURLProtocol.requests(for: base).first)
    #expect((try body(sent)["thinking"] as? [String: String]) == ["type": "disabled"])
  }

  @Test(arguments: ["claude-sonnet-5-5", "gpt-4o", "sonnet"]) func otherModelsKeepTheirOwnDefault(
    model: String
  ) async throws {
    let base = StubURLProtocol.register(reply("ok"))
    _ = try await summarizer(base, model: model).summarize(entries)
    let sent = try #require(StubURLProtocol.requests(for: base).first)
    #expect(try body(sent)["thinking"] == nil)
  }

  @Test func theTextBlocksAreJoined() async throws {
    let base = StubURLProtocol.register(
      Stub(
        headers: json,
        lines: [
          #"{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"one"},{"type":"text","text":"two"}]}"#
        ]))
    #expect(try await summarizer(base).summarize(entries) == "one\ntwo")
  }

  @Test(arguments: [401, 403]) func rejectedCredentialsAreUnauthorized(status: Int) async {
    let base = StubURLProtocol.register(Stub(status: status, headers: json))
    await #expect(throws: NtfyError.unauthorized) { try await summarizer(base).summarize(entries) }
  }

  @Test func aThrottledRequestCarriesTheRetryDelay() async {
    let base = StubURLProtocol.register(
      Stub(status: 429, headers: json.merging(["Retry-After": "12"]) { $1 }))
    await #expect(throws: NtfyError.rateLimited(retryAfter: 12)) {
      try await summarizer(base).summarize(entries)
    }
  }

  @Test(arguments: [500, 502, 529]) func aServerErrorIsUnreachable(status: Int) async {
    let base = StubURLProtocol.register(Stub(status: status, headers: json))
    await #expect(throws: NtfyError.serverUnreachable) {
      try await summarizer(base).summarize(entries)
    }
  }

  @Test func aRejectedRequestNamesItsReason() async {
    let base = StubURLProtocol.register(
      Stub(
        status: 404, headers: json,
        lines: [#"{"type":"error","error":{"type":"not_found_error","message":"model: nope"}}"#]))
    await #expect(throws: NtfyError.invalidResponse("HTTP 404: model: nope")) {
      try await summarizer(base, model: "nope").summarize(entries)
    }
  }

  @Test func aRejectedRequestWithoutABodyStillSaysTheStatus() async {
    let base = StubURLProtocol.register(Stub(status: 400, headers: json))
    await #expect(throws: NtfyError.invalidResponse("HTTP 400")) {
      try await summarizer(base).summarize(entries)
    }
  }

  @Test func aReplyWithoutTextIsInvalid() async {
    let base = StubURLProtocol.register(Stub(headers: json, lines: [#"{"content":[]}"#]))
    await #expect(throws: NtfyError.invalidResponse("no text in the response")) {
      try await summarizer(base).summarize(entries)
    }
  }

  @Test func somethingThatIsNotJSONIsInvalid() async {
    let base = StubURLProtocol.register(
      Stub(headers: ["Content-Type": "text/html"], lines: ["<html>"]))
    await #expect(throws: NtfyError.self) { try await summarizer(base).summarize(entries) }
  }

  @Test func aRedirectIsNeverFollowed() async throws {
    let target = try #require(URL(string: "https://elsewhere.test/v1/messages"))
    let base = StubURLProtocol.register(Stub(status: 302, headers: json, redirectTo: target))
    await #expect(throws: NtfyError.redirected) { try await summarizer(base).summarize(entries) }
    #expect(StubURLProtocol.requests(for: target).isEmpty)
  }

  @Test func aSilentEndpointTimesOut() async {
    let base = StubURLProtocol.register(Stub(stall: true))
    await #expect(throws: NtfyError.serverUnreachable) {
      try await summarizer(base, timeout: 0.3).summarize(entries)
    }
  }

  @Test func theKeyNeverTravelsOverPlainHttpWithoutTheOptIn() async {
    let base = StubURLProtocol.register(reply("ok"), scheme: "http")
    await #expect(throws: NtfyError.insecureServer) {
      try await summarizer(base).summarize(entries)
    }
    #expect(StubURLProtocol.requests(for: base).isEmpty)
    #expect((try? await summarizer(base, allowInsecure: true).summarize(entries)) == "ok")
  }

  @Test func theFactoryRefusesAnAddressThatIsNoUrl() {
    #expect(
      AnthropicSummarizer.make(endpoint: "not a url", key: "k", model: "m", allowInsecure: false)
        == nil)
    #expect(
      AnthropicSummarizer.make(
        endpoint: "https://api.anthropic.com/", key: "k", model: "m", allowInsecure: false) != nil)
  }
}

extension URLRequest {
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
