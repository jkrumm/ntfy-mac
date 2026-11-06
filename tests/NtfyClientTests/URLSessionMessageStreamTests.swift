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
    var events: [StreamEvent] = []
    var error: NtfyError?

    var ids: [String] {
      events.compactMap { event in
        guard case .message(let message) = event else { return nil }
        return message.id
      }
    }
  }

  private func run(
    _ stub: Stub, token: String? = "tk", base: URL? = nil, allowInsecure: Bool = false,
    connectTimeout: Duration = .seconds(30),
    diagnostics: @escaping @Sendable (String) -> Void = { _ in }
  ) async -> (outcome: Outcome, base: URL) {
    let base = base ?? StubURLProtocol.register(stub)
    let stream = URLSessionMessageStream(
      base: base, token: token, allowInsecure: allowInsecure, connectTimeout: connectTimeout,
      session: StubURLProtocol.session(), diagnostics: diagnostics)
    var outcome = Outcome()
    do {
      for try await event in stream.events(topics: ["t"], since: nil) {
        outcome.events.append(event)
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
    let garbage = Stub(status: 429, headers: ["Retry-After": "-3"])
    #expect(await run(garbage).outcome.error == .rateLimited(retryAfter: nil))
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
    #expect(outcome.error == .invalidResponse("expected JSON, got text/html"))
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

  @Test func yieldsEveryKnownEventTypeAndSkipsUnknownOnes() async {
    let lines = [
      #"{"id":"o","time":1,"event":"open","topic":"t"}"#,
      #"{"id":"k","time":1,"event":"keepalive","topic":"t"}"#,
      #"{"id":"p","time":1,"event":"poll_request","topic":"t"}"#,
      Self.line("1"),
      #"{"id":"d","time":1,"event":"message_delete","topic":"t","sequence_id":"s"}"#,
      #"{"id":"c","time":1,"event":"message_clear","topic":"t","sequence_id":"s"}"#,
      #"{"id":"f","time":1,"event":"future","topic":"t"}"#,
    ]
    let (outcome, _) = await run(Stub(lines: lines))
    #expect(outcome.error == nil)
    #expect(outcome.events.count == 6)
    #expect(Array(outcome.events.prefix(3)) == [.open, .keepalive, .pollRequest])
    #expect(outcome.ids == ["1"])
    #expect(
      Array(outcome.events.suffix(2)) == [
        .messageDelete(topic: "t", sequenceID: "s"), .messageClear(topic: "t", sequenceID: "s"),
      ])
  }

  @Test func plainHttpWithTokenIsRefusedBeforeAnyRequest() async {
    let base = StubURLProtocol.register(Stub(lines: [Self.line("1")]), scheme: "http")
    let (outcome, _) = await run(Stub(), base: base)
    #expect(outcome.error == .insecureServer)
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func plainHttpIsAllowedOnOptInAndWithoutToken() async {
    let optIn = StubURLProtocol.register(Stub(lines: [Self.line("1")]), scheme: "http")
    #expect(await run(Stub(), base: optIn, allowInsecure: true).outcome.ids == ["1"])
    let anonymous = StubURLProtocol.register(Stub(lines: [Self.line("2")]), scheme: "http")
    #expect(await run(Stub(), token: nil, base: anonymous).outcome.ids == ["2"])
  }

  @Test func loopbackHttpIsAllowedWithToken() async {
    let base = StubURLProtocol.register(
      Stub(lines: [Self.line("1")]), scheme: "http", host: "localhost")
    #expect(await run(Stub(), base: base).outcome.ids == ["1"])
  }

  @Test func silentServerHitsTheConnectTimeout() async {
    let (outcome, base) = await run(Stub(stall: true), connectTimeout: .milliseconds(100))
    #expect(outcome.error == .serverUnreachable)
    #expect(await StubURLProtocol.waitUntilStopped(base))
  }

  @Test func openBodyHasNoTimeout() async {
    // The first message proves the connection came up inside the connect timeout; the stream
    // must then outlive that timeout. Event-driven, so a slow runner only delays the check.
    let connectTimeout = Duration.seconds(1)
    let stub = Stub(lines: [Self.line("1")], hold: true)
    let base = StubURLProtocol.register(stub)
    let stream = URLSessionMessageStream(
      base: base, token: nil, connectTimeout: connectTimeout, session: StubURLProtocol.session())
    let (arrivals, signal) = AsyncStream<Void>.makeStream()
    let started = ContinuousClock.now
    let consumer = Task { () -> [String] in
      defer { signal.finish() }
      var ids: [String] = []
      for try await event in stream.events(topics: ["t"], since: nil) {
        if case .message(let message) = event {
          ids.append(message.id)
          signal.yield()
        }
      }
      return ids
    }
    for await _ in arrivals { break }
    try? await Task.sleep(until: started + connectTimeout * 1.5)
    consumer.cancel()
    #expect((try? await consumer.value) == ["1"])
  }

  @Test func invalidTopicsFailBeforeAnyRequest() async {
    let base = StubURLProtocol.register(Stub())
    let stream = URLSessionMessageStream(base: base, token: nil, session: StubURLProtocol.session())
    var failure: NtfyError?
    do {
      for try await _ in stream.events(topics: ["bad topic"], since: nil) {}
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
        for try await _ in stream.events(topics: ["t"], since: nil) {
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
    #expect(await StubURLProtocol.waitUntilStopped(base))
  }
}
