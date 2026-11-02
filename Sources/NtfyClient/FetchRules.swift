import Foundation
import NtfyCore

/// What the image and attachment fetchers share: where they may connect and who gets the token.
enum FetchRules {
  /// The configured server's own origin is trusted. Any other host must resolve to public
  /// addresses only, so a sender cannot make the app fetch from the local network.
  static func isReachable(_ url: URL, server: URL, resolver: any HostResolving) async -> Bool {
    if ServerResponse.sameOrigin(url, server) { return true }
    guard let host = url.host() else { return false }
    return await HostSafety.resolvesToPublicAddresses(host, using: resolver)
  }

  /// A GET that carries the bearer token only to the server's own origin, and only over a
  /// connection `ServerEndpoint` would send a token on.
  static func request(
    _ url: URL, server: URL, token: @Sendable () async -> String?, allowInsecure: Bool,
    timeout: TimeInterval
  ) async -> URLRequest {
    var bearer: String?
    if ServerResponse.sameOrigin(url, server) {
      let candidate = await token()
      let allowed =
        (try? ServerEndpoint.url(
          base: server, path: "", token: candidate, allowInsecure: allowInsecure)) != nil
      bearer = allowed ? candidate : nil
    }
    return URLRequest.authorized(url, token: bearer, timeout: timeout)
  }
}
