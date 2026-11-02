import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct URLSessionHTTPActionRunnerTests {
  private func runner(timeout: TimeInterval = 10) -> URLSessionHTTPActionRunner {
    URLSessionHTTPActionRunner(timeout: timeout, session: StubURLProtocol.session())
  }

  private func call(
    _ url: URL, method: String = "POST", headers: [String: String] = [:], body: String? = nil
  ) -> HTTPCall {
    HTTPCall(url: url, method: method, headers: headers, body: body)
  }

  private func failure(of call: HTTPCall, timeout: TimeInterval = 10) async -> NtfyError? {
    do {
      try await runner(timeout: timeout).run(call)
      return nil
    } catch {
      return error
    }
  }

  @Test func sendsMethodHeadersAndBody() async throws {
    let base = StubURLProtocol.register(Stub(status: 204))
    try await runner().run(
      call(base, method: "put", headers: ["X-Thing": "1"], body: "payload"))
    let request = try #require(StubURLProtocol.requests(for: base).first)
    #expect(request.httpMethod == "PUT")
    #expect(request.value(forHTTPHeaderField: "X-Thing") == "1")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test func bodyArrivesInTheRequest() async throws {
    let base = StubURLProtocol.register(Stub())
    try await runner().run(call(base, body: "payload"))
    let request = try #require(StubURLProtocol.requests(for: base).first)
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 64)
    let count = stream.read(&buffer, maxLength: buffer.count)
    #expect(String(bytes: buffer.prefix(count), encoding: .utf8) == "payload")
  }

  @Test func methodDefaultsComeFromTheCaller() async throws {
    let base = StubURLProtocol.register(Stub())
    try await runner().run(call(base))
    #expect(StubURLProtocol.requests(for: base).first?.httpMethod == "POST")
  }

  @Test func senderAuthorizationIsKeptButHopByHopHeadersAreDropped() async throws {
    let base = StubURLProtocol.register(Stub())
    let headers = [
      "Authorization": "Basic abc", "Host": "evil.example.com", "Connection": "close",
      "Transfer-Encoding": "chunked", "Bad Name": "x", "X-Ok": "line\r\nInjected: 1",
    ]
    try await runner().run(call(base, headers: headers))
    let request = try #require(StubURLProtocol.requests(for: base).first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic abc")
    #expect(request.value(forHTTPHeaderField: "Host") == nil)
    #expect(request.value(forHTTPHeaderField: "Connection") == nil)
    #expect(request.value(forHTTPHeaderField: "Transfer-Encoding") == nil)
    #expect(request.value(forHTTPHeaderField: "X-Ok") == nil)
  }

  @Test func nonSuccessStatusFails() async {
    let base = StubURLProtocol.register(Stub(status: 500))
    #expect(await failure(of: call(base)) == .invalidResponse("http action failed (500)"))
  }

  @Test func redirectIsNotFollowedAndCountsAsFailure() async {
    let target = StubURLProtocol.register(Stub())
    let base = StubURLProtocol.register(Stub(redirectTo: target))
    #expect(await failure(of: call(base)) == .invalidResponse("http action failed (302)"))
    #expect(StubURLProtocol.requests(for: target).isEmpty)
  }

  @Test func oversizeBodyIsRefusedBeforeSending() async {
    let base = StubURLProtocol.register(Stub())
    let body = String(repeating: "a", count: URLSessionHTTPActionRunner.maxBodyBytes + 1)
    let result = await failure(of: call(base, body: body))
    #expect(result == .invalidResponse("http action body exceeds 65536 bytes"))
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func bodyAtTheLimitIsSent() async throws {
    let base = StubURLProtocol.register(Stub())
    let body = String(repeating: "a", count: URLSessionHTTPActionRunner.maxBodyBytes)
    try await runner().run(call(base, body: body))
    #expect(StubURLProtocol.requests(for: base).count == 1)
  }

  @Test func nonWebSchemesAreRefused() async throws {
    let url = try #require(URL(string: "ftp://example.com/x"))
    #expect(await failure(of: call(url)) == .invalidResponse("http action needs an http(s) URL"))
  }

  @Test func transportFailureIsServerUnreachable() async throws {
    let unknown = try #require(URL(string: "https://\(UUID().uuidString.lowercased()).test"))
    #expect(await failure(of: call(unknown)) == .serverUnreachable)
  }

  @Test func silentServerTimesOut() async {
    let base = StubURLProtocol.register(Stub(stall: true))
    #expect(await failure(of: call(base), timeout: 0.1) == .serverUnreachable)
  }
}
