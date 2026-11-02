import Foundation
import NtfyCore

/// URL rules shared by every client that talks to the configured server.
enum ServerEndpoint {
  /// Resolves `path` and `query` against `base`, refusing anything that would put a token on an
  /// unprotected connection: `https`, a loopback host, or an explicit `allowInsecure` opt-in.
  static func url(
    base: URL, path: String, query: [URLQueryItem] = [], token: String?, allowInsecure: Bool
  ) throws(NtfyError) -> URL {
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = components.host?.lowercased().trimmingCharacters(in: ["[", "]"]), !host.isEmpty
    else {
      throw .invalidResponse("server URL must be http(s) with a host")
    }
    if token != nil, scheme == "http", !allowInsecure, !loopbackHosts.contains(host) {
      throw .insecureServer
    }
    var basePath = components.percentEncodedPath
    if !basePath.hasSuffix("/") { basePath += "/" }
    components.percentEncodedPath = basePath + path
    components.fragment = nil
    components.percentEncodedQuery = nil
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw .invalidResponse("malformed server URL") }
    return url
  }

  private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
}

extension URLRequest {
  /// A GET that carries the bearer token, if any.
  static func authorized(_ url: URL, token: String?, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }
}
