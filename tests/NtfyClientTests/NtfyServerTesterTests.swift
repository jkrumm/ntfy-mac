import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct NtfyServerTesterTests {
  private func tester() -> NtfyServerTester {
    NtfyServerTester(timeout: 2, session: StubURLProtocol.session())
  }

  private func serve(_ stub: Stub, scheme: String = "https", host: String? = nil) -> URL {
    StubURLProtocol.register(stub, scheme: scheme, host: host)
  }

  private let json = ["Content-Type": "application/json"]

  @Test func anAcceptedTokenReturnsTheTopics() async {
    let base = serve(
      Stub(
        headers: json,
        lines: [#"{"subscriptions":[{"topic":"alerts"},{"topic":"ops"},{"topic":"alerts"}]}"#]))
    let result = await tester().test(url: base.absoluteString, token: "tk", allowInsecure: false)
    #expect(result == .ok(topics: ["alerts", "ops"]))
    #expect(
      StubURLProtocol.requests(for: base).first?.value(forHTTPHeaderField: "Authorization")
        == "Bearer tk")
  }

  @Test func aBareHostIsTestedOverHttps() async {
    let host = "\(UUID().uuidString.lowercased()).test"
    _ = serve(Stub(headers: json, lines: [#"{"subscriptions":[]}"#]), host: host)
    let result = await tester().test(url: host, token: "tk", allowInsecure: false)
    #expect(result == .ok(topics: []))
  }

  @Test(arguments: [401, 403]) func rejectedCredentialsAreUnauthorized(status: Int) async {
    let base = serve(Stub(status: status, headers: json))
    let result = await tester().test(url: base.absoluteString, token: "tk", allowInsecure: false)
    #expect(result == .unauthorized)
  }

  @Test func aServerErrorIsUnreachable() async {
    let base = serve(Stub(status: 503, headers: json))
    let result = await tester().test(url: base.absoluteString, token: "tk", allowInsecure: false)
    #expect(result == .unreachable)
  }

  @Test func aSilentServerTimesOut() async {
    let base = serve(Stub(stall: true))
    let quick = NtfyServerTester(timeout: 0.3, session: StubURLProtocol.session())
    let result = await quick.test(url: base.absoluteString, token: "tk", allowInsecure: false)
    #expect(result == .unreachable)
  }

  @Test func aRedirectIsNeverFollowed() async {
    let target = URL(string: "https://elsewhere.test/v1/account")
    let base = serve(Stub(status: 302, headers: json, redirectTo: target))
    let result = await tester().test(url: base.absoluteString, token: "tk", allowInsecure: false)
    #expect(result == .redirected)
  }

  @Test func plainHttpWithATokenNeedsTheOptIn() async {
    let base = serve(Stub(headers: json, lines: [#"{"subscriptions":[]}"#]), scheme: "http")
    let refused = await tester().test(url: base.absoluteString, token: "tk", allowInsecure: false)
    #expect(refused == .insecure)
    #expect(StubURLProtocol.requests(for: base).isEmpty)
    let allowed = await tester().test(url: base.absoluteString, token: "tk", allowInsecure: true)
    #expect(allowed == .ok(topics: []))
  }

  @Test func somethingThatIsNotNtfyIsInvalid() async {
    let base = serve(Stub(headers: json, lines: ["[1, 2]"]))
    let result = await tester().test(url: base.absoluteString, token: "tk", allowInsecure: false)
    guard case .invalid(let reason) = result else {
      Issue.record("expected invalid, got \(result)")
      return
    }
    #expect(reason.contains("ntfy"))
  }

  @Test(arguments: ["", "ftp://x.example.com", "https://"])
  func anUnusableAddressIsInvalidWithoutARequest(url: String) async {
    let result = await tester().test(url: url, token: "tk", allowInsecure: false)
    guard case .invalid = result else {
      Issue.record("expected invalid, got \(result)")
      return
    }
  }
}
