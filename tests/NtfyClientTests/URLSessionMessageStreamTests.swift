import Foundation
import NtfyCore
import Synchronization
import Testing

@testable import NtfyClient

@Suite struct URLSessionMessageStreamTests {
  private static func line(_ id: String) -> String {
    #"{"id":"\#(id)","time":1,"event":"message","topic":"t","message":"m"}"#
  }

  private struct Outcome {
    var ids: [String] = []
    var error: NtfyError?
  }

  private func run(
    _ stub: Stub, token: String? = "tk",
    diagnostics: @escaping @Sendable (String) -> Void = { _ in }
  ) async -> (outcome: Outcome, base: URL) {
    let base = StubURLProtocol.register(stub)
    let stream = URLSessionMessageStream(
      base: base, token: token, session: StubURLProtocol.session(), diagnostics: diagnostics)
    var outcome = Outcome()
    do {
      for try await message in stream.messages(topics: ["t"], since: nil) {
        outcome.ids.append(message.id)
      }
    } catch {
      outcome.error = error as? NtfyError
    }
    return (outcome, base)
  }

  @Test func streamsMessagesAndSendsBearerToken() async {
    let (outcome, base) = await run(Stub(lines: [Self.line("1"), Self.line("2")]))
    #expect(outcome.ids == ["1", "2"])
    #expect(outcome.error == nil)
    let request = StubURLProtocol.requests(for: base).first
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer tk")
    #expect(request?.url?.path == "/t/json")
  }

  @Test func omitsAuthorizationWithoutToken() async {
    let (_, base) = await run(Stub(lines: [Self.line("1")]), token: nil)
    let request = StubURLProtocol.requests(for: base).first
    #expect(request?.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test(arguments: [401, 403])
  func authFailuresAreUnauthorized(status: Int) async {
    let (outcome, _) = await run(Stub(status: status))
    #expect(outcome.error == .unauthorized)
  }

  @Test func rateLimitCarriesRetryAfter() async {
    let stub = Stub(status: 429, headers: ["Retry-After": "30"])
    #expect(await run(stub).outcome.error == .rateLimited(retryAfter: 30))
    #expect(await run(Stub(status: 429)).outcome.error == .rateLimited(retryAfter: nil))
  }

  @Test(arguments: [500, 502, 503])
  func serverErrorsAreUnreachable(status: Int) async {
    #expect(await run(Stub(status: status)).outcome.error == .serverUnreachable)
  }

  @Test func otherClientErrorsAreInvalidResponses() async {
    #expect(await run(Stub(status: 404)).outcome.error == .invalidResponse("HTTP 404"))
  }

  @Test func redirectsAreRefusedAndTokenNeverReachesTheTarget() async {
    let target = StubURLProtocol.register(Stub(lines: [Self.line("evil")]))
    let (outcome, _) = await run(Stub(redirectTo: target))
    #expect(outcome.error == .redirected)
    #expect(outcome.ids.isEmpty)
    #expect(StubURLProtocol.requests(for: target).isEmpty)
  }

  @Test func foreignResponseOriginIsTerminal() async {
    let other = URL(string: "https://elsewhere.test")!
    let (outcome, _) = await run(Stub(lines: [Self.line("1")], respondFrom: other))
    #expect(outcome.error == .redirected)
    #expect(outcome.ids.isEmpty)
  }

  @Test func htmlFromAProxyIsNotAStream() async {
    let stub = Stub(headers: ["Content-Type": "text/html"], lines: ["<html>captive portal</html>"])
    let (outcome, _) = await run(stub)
    #expect(outcome.error == .invalidResponse("expected an NDJSON stream, got text/html"))
    #expect(outcome.ids.isEmpty)
  }

  @Test func badLinesAreSkippedAndReported() async {
    let skipped = Mutex(0)
    let stub = Stub(lines: [Self.line("1"), "garbage", #"{"id":"x"}"#, Self.line("2")])
    let (outcome, _) = await run(stub) { _ in skipped.withLock { $0 += 1 } }
    #expect(outcome.ids == ["1", "2"])
    #expect(outcome.error == nil)
    #expect(skipped.withLock { $0 } == 2)
  }

  @Test func unknownEventsAreIgnored() async {
    let keepalive = #"{"id":"k","time":1,"event":"keepalive","topic":"t"}"#
    let (outcome, _) = await run(Stub(lines: [keepalive, Self.line("1")]))
    #expect(outcome.ids == ["1"])
  }

  @Test func invalidTopicsFailBeforeAnyRequest() async {
    let base = StubURLProtocol.register(Stub())
    let stream = URLSessionMessageStream(base: base, token: nil, session: StubURLProtocol.session())
    var failure: NtfyError?
    do {
      for try await _ in stream.messages(topics: ["bad topic"], since: nil) {}
    } catch {
      failure = error as? NtfyError
    }
    #expect(failure == .invalidTopic("bad topic"))
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func cancellationFinishesCleanlyAndStopsTheRequest() async {
    let base = StubURLProtocol.register(Stub(lines: [Self.line("1")], hold: true))
    let stream = URLSessionMessageStream(base: base, token: nil, session: StubURLProtocol.session())
    let (signal, signalContinuation) = AsyncStream<Void>.makeStream()
    let consumer = Task { () -> NtfyError? in
      do {
        for try await _ in stream.messages(topics: ["t"], since: nil) {
          signalContinuation.yield()
        }
        return nil
      } catch {
        return error as? NtfyError ?? .invalidResponse("not an NtfyError")
      }
    }
    for await _ in signal { break }
    consumer.cancel()
    #expect(await consumer.value == nil)
    for _ in 0..<1000 where !StubURLProtocol.isStopped(base) { await Task.yield() }
    #expect(StubURLProtocol.isStopped(base))
  }
}
