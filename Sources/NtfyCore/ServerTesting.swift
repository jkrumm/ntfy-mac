/// What a connection test found out about a server and a token.
public enum ServerTestResult: Sendable, Hashable {
  /// The server answered and accepted the token; these are the account's topics.
  case ok(topics: [String])  // swiftlint:disable:this identifier_name
  /// The server rejected the token.
  case unauthorized
  /// No answer: wrong host, no network, a timeout or a server error.
  case unreachable
  /// The token would travel over plain http to a non-loopback host, and `allowInsecure` is off.
  case insecure
  /// The server redirected; the token is never sent to another address.
  case redirected
  /// The address or the answer is not usable; the reason says what.
  case invalid(reason: String)
}

/// Checks that a server address and token work, without saving anything.
public protocol ServerTesting: Sendable {
  /// Applies the stream's rules: https unless `allowInsecure` (or loopback), no redirects, the
  /// token goes to the given host only, and the call times out.
  func test(url: String, token: String, allowInsecure: Bool) async -> ServerTestResult
}
