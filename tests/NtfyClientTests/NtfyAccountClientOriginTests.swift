import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct NtfyAccountClientOriginTests {
  /// Serves `subscriptions` (JSON array body, `$HOST` replaced by the stub host) from one stub host.
  private func topics(_ subscriptions: String) async throws -> [String] {
    let host = "\(UUID().uuidString.lowercased()).test"
    let list =
      subscriptions
      .replacingOccurrences(of: "$HOSTUP", with: host.uppercased())
      .replacingOccurrences(of: "$HOST", with: host)
    let body = #"{"subscriptions":\#(list)}"#
    let base = StubURLProtocol.register(
      Stub(headers: ["Content-Type": "application/json"], lines: [body]), host: host)
    let client = NtfyAccountClient(base: base, token: "tk", session: StubURLProtocol.session())
    return try await client.subscribedTopics()
  }

  @Test func keepsOnlyThisServersSubscriptions() async throws {
    let result = try await topics(
      """
      [{"base_url":"https://$HOST","topic":"mine"},
       {"base_url":"https://other.example.com","topic":"theirs"},
       {"base_url":"http://$HOST","topic":"wrong-scheme"},
       {"base_url":"https://$HOST:8443","topic":"wrong-port"}]
      """)
    #expect(result == ["mine"])
  }

  @Test func hostIsCaseInsensitiveAndTrailingSlashIgnored() async throws {
    let result = try await topics(
      #"[{"base_url":"HTTPS://$HOSTUP/","topic":"a"},{"base_url":"https://$HOST/","topic":"b"}]"#)
    #expect(result == ["a", "b"])
  }

  @Test func entriesWithoutABaseURLAreKept() async throws {
    let result = try await topics(
      #"[{"topic":"bare"},{"base_url":"https://elsewhere.example.com","topic":"x"}]"#)
    #expect(result == ["bare"])
  }

  @Test func unparseableBaseURLIsDropped() async throws {
    #expect(try await topics(#"[{"base_url":"::not a url","topic":"x"}]"#).isEmpty)
  }

  @Test func defaultPortsMatchExplicitOnes() async throws {
    let result = try await topics(#"[{"base_url":"https://$HOST:443","topic":"a"}]"#)
    #expect(result == ["a"])
  }
}
