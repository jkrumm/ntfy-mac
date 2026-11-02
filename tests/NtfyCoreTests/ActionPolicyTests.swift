import Foundation
import Testing

@testable import NtfyCore

@Suite struct ActionPolicyTests {
  private static func http(_ url: String?) -> MessageAction {
    MessageAction(kind: .http, label: "Go", url: url.flatMap { URL(string: $0) })
  }

  private static func view(_ url: String?) -> MessageAction {
    MessageAction(kind: .view, label: "Open", url: url.flatMap { URL(string: $0) })
  }

  private func isAllow(_ decision: ActionDecision) -> Bool { decision == .allow }

  @Test(arguments: [
    "https://example.com", "http://example.com/x", "mailto:a@example.com", "HTTPS://Example.com",
  ])
  func viewAllowsOpenableURLs(url: String) {
    #expect(ActionPolicy.evaluate(Self.view(url), config: Config()) == .allow)
  }

  @Test(arguments: [nil, "javascript:alert(1)", "file:///x", "myapp://x", "http://"])
  func viewDeniesTheRest(url: String?) {
    guard case .deny = ActionPolicy.evaluate(Self.view(url), config: Config()) else {
      Issue.record("expected deny for \(url ?? "nil")")
      return
    }
  }

  @Test(arguments: [
    "https://example.com/hook", "http://example.com", "https://8.8.8.8/x", "https://1.1.1.1",
    "https://100.63.255.255", "https://100.128.0.1", "https://172.15.0.1", "https://172.32.0.1",
    "https://11.0.0.1", "https://192.169.0.1", "https://169.253.1.1",
    "https://[2001:4860:4860::8888]/", "https://[2606:4700::1111]/", "https://sub.example.com.",
  ])
  func httpAllowsPublicTargets(url: String) {
    #expect(ActionPolicy.evaluate(Self.http(url), config: Config()) == .allow)
  }

  @Test(arguments: [
    "http://localhost:8080", "http://LOCALHOST", "http://foo.localhost", "http://127.0.0.1",
    "http://127.1", "http://2130706433", "http://0x7f000001", "http://0.0.0.0",
    "http://10.1.2.3", "http://172.16.0.1", "http://172.31.255.255", "http://192.168.1.1",
    "http://169.254.169.254", "http://100.64.0.1", "http://100.100.100.100",
    "http://100.127.255.255", "http://[::1]/", "http://[::]/", "http://[fd00::1]/",
    "http://[fc00::1]/", "http://[fe80::1]/", "http://[febf::1]/", "http://[::ffff:10.0.0.1]/",
    "http://[::ffff:127.0.0.1]/", "http://printer.local", "http://nas.internal",
    "http://nas.internal.", "http://router", "http://myhost:3000", "https://localhost",
  ])
  func httpConfirmsPrivateTargets(url: String) {
    guard case .confirm = ActionPolicy.evaluate(Self.http(url), config: Config()) else {
      Issue.record("expected confirm for \(url)")
      return
    }
  }

  @Test(arguments: [
    "http://localhost", "http://192.168.1.1", "http://100.64.0.1", "http://[fd00::1]/",
    "http://router",
  ])
  func optInAllowsPrivateTargets(url: String) {
    let config = Config(allowPrivateNetworkActions: true)
    #expect(ActionPolicy.evaluate(Self.http(url), config: config) == .allow)
  }

  @Test(arguments: ["ftp://example.com/x", "file:///etc/passwd", "myapp://run", "ssh://host"])
  func httpConfirmsNonWebSchemesEvenWithOptIn(url: String) {
    let config = Config(allowPrivateNetworkActions: true)
    guard case .confirm = ActionPolicy.evaluate(Self.http(url), config: config) else {
      Issue.record("expected confirm for \(url)")
      return
    }
  }

  @Test(arguments: [nil, "example.com/hook", "/just/a/path", "http://", "https:///x"])
  func httpDeniesMissingTargets(url: String?) {
    guard case .deny = ActionPolicy.evaluate(Self.http(url), config: Config()) else {
      Issue.record("expected deny for \(url ?? "nil")")
      return
    }
  }

  @Test func unsupportedKindsAreDenied() {
    for kind in [MessageAction.Kind.broadcast, .copy, .unknown("x")] {
      let action = MessageAction(kind: kind, label: "L", url: URL(string: "https://example.com"))
      guard case .deny = ActionPolicy.evaluate(action, config: Config()) else {
        Issue.record("expected deny for \(kind)")
        continue
      }
    }
  }
}
