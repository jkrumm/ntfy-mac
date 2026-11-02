import Foundation
import NtfyCore

/// Status, origin and content-type handling shared by every client.
enum ServerResponse {
  /// Throws the `NtfyError` for anything but a same-origin 2xx JSON response.
  static func validate(
    _ response: URLResponse, requested: URL?, now: Date = Date()
  ) throws(NtfyError) {
    guard let http = response as? HTTPURLResponse else {
      throw .invalidResponse("not an HTTP response")
    }
    if let requested, let final = http.url, !sameOrigin(requested, final) {
      throw .redirected
    }
    switch http.statusCode {
    case 200..<300:
      let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased()
      if let type, !type.contains("json") {
        throw .invalidResponse("expected JSON, got \(type)")
      }
    case 300..<400: throw .redirected
    case 401, 403: throw .unauthorized
    case 429:
      let header = http.value(forHTTPHeaderField: "Retry-After")
      throw .rateLimited(retryAfter: RetryAfter.seconds(from: header, now: now))
    case 500..<600: throw .serverUnreachable
    default: throw .invalidResponse("HTTP \(http.statusCode)")
    }
  }

  /// Collapses whatever a URLSession call threw into the port's error type.
  static func error(from error: any Error) -> NtfyError {
    (error as? NtfyError) ?? .serverUnreachable
  }

  static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
    func origin(_ url: URL) -> [String?] {
      let scheme = url.scheme?.lowercased()
      let port = url.port ?? (scheme == "https" ? 443 : 80)
      return [scheme, url.host?.lowercased(), String(port)]
    }
    return origin(lhs) == origin(rhs)
  }
}

/// Parses the `Retry-After` header: delay seconds or an HTTP-date.
enum RetryAfter {
  /// Longest wait honoured; a server asking for more is treated as asking for this.
  static let cap = 86_400

  /// `nil` for a missing, negative or unparseable value, or a date in the past.
  static func seconds(from header: String?, now: Date) -> Int? {
    guard let value = header?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
      return nil
    }
    if value.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) {
      return Int(value).map { min($0, cap) } ?? cap
    }
    guard let date = httpDate(value) else { return nil }
    let delta = date.timeIntervalSince(now).rounded(.up)
    guard delta >= 0 else { return nil }
    return Int(min(delta, Double(cap)))
  }

  /// IMF-fixdate, the only format HTTP/1.1 senders may produce (RFC 9110 section 5.6.7).
  private static func httpDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return formatter.date(from: value)
  }
}

/// Redirects are terminal: following one would send the token to whatever host answered.
final class RedirectRefuser: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}

/// Runs `operation`, failing with `.serverUnreachable` if it has not finished within `limit`.
func withTimeout<T: Sendable>(
  _ limit: Duration, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(for: limit)
      throw NtfyError.serverUnreachable
    }
    defer { group.cancelAll() }
    guard let first = try await group.next() else { throw NtfyError.serverUnreachable }
    return first
  }
}
