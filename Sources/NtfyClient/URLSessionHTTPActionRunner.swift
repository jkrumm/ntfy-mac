import Foundation
import NtfyCore

/// `HTTPActionRunning` over HTTP.
///
/// The caller has already run `ActionPolicy`; this type only enforces transport limits. It has
/// no access to the ntfy token, so that can never leak into a request a message asked for. Headers
/// are the sender's own, including an `Authorization` for the sender's own target; hop-by-hop
/// headers, `Host` and malformed names or values are dropped. Redirects are not followed (a 3xx
/// counts as a failure) and the response body is never read.
public struct URLSessionHTTPActionRunner: HTTPActionRunning {
  public static let maxBodyBytes = 64 * 1024

  private static let dropped: Set<String> = [
    "host", "content-length", "connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "proxy-connection", "te", "trailer", "transfer-encoding", "upgrade",
  ]

  private let timeout: TimeInterval
  private let session: URLSession

  public init(
    timeout: TimeInterval = 10, session: URLSession = URLSession(configuration: .ephemeral)
  ) {
    self.timeout = timeout
    self.session = session
  }

  public func run(_ call: HTTPCall) async throws(NtfyError) {
    let request = try makeRequest(call)
    let (session, limit) = (session, Duration.seconds(timeout))
    let status: Int
    do {
      status = try await withTimeout(limit) {
        let (_, response) = try await session.bytes(for: request, delegate: RedirectRefuser())
        return (response as? HTTPURLResponse)?.statusCode ?? 0
      }
    } catch {
      throw .serverUnreachable
    }
    guard (200..<300).contains(status) else {
      throw .invalidResponse("http action failed (\(status))")
    }
  }

  private func makeRequest(_ call: HTTPCall) throws(NtfyError) -> URLRequest {
    guard URLPolicy.imageURL(call.url) != nil else {
      throw .invalidResponse("http action needs an http(s) URL")
    }
    guard call.method.utf8.allSatisfy({ Self.isTokenCharacter($0) }), !call.method.isEmpty else {
      throw .invalidResponse("http action has an invalid method")
    }
    let body = call.body.map { Data($0.utf8) }
    if let body, body.count > Self.maxBodyBytes {
      throw .invalidResponse("http action body exceeds \(Self.maxBodyBytes) bytes")
    }
    var request = URLRequest(url: call.url)
    request.httpMethod = call.method.uppercased()
    request.timeoutInterval = timeout
    request.httpBody = body
    for (name, value) in call.headers where Self.isForwardable(name, value) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    return request
  }

  private static func isForwardable(_ name: String, _ value: String) -> Bool {
    !name.isEmpty && name.utf8.allSatisfy(isTokenCharacter) && !dropped.contains(name.lowercased())
      && !value.utf8.contains { $0 == 0x0D || $0 == 0x0A || $0 == 0x00 }
  }

  /// RFC 9110 `tchar`.
  private static func isTokenCharacter(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
      UInt8(ascii: "0")...UInt8(ascii: "9"):
      true
    default:
      "!#$%&'*+-.^_`|~".utf8.contains(byte)
    }
  }
}
