import Foundation
import Synchronization

/// One scripted server response, registered under a unique host so tests never share state.
struct Stub: Sendable {
  var status = 200
  var headers = ["Content-Type": "application/x-ndjson; charset=utf-8"]
  var lines: [String] = []
  /// Answer with a 302 to this URL instead of a body.
  var redirectTo: URL?
  /// Report this URL as the response's origin (as a transparently followed redirect would).
  var respondFrom: URL?
  /// Keep the connection open after the body, like a live stream.
  var hold = false
}

final class StubURLProtocol: URLProtocol {
  private struct Record {
    var stub: Stub
    var requests: [URLRequest] = []
    var stopped = false
  }

  private static let records = Mutex<[String: Record]>([:])

  /// Registers a stub and returns the base URL that reaches it.
  static func register(_ stub: Stub) -> URL {
    let host = "\(UUID().uuidString.lowercased()).test"
    records.withLock { $0[host] = Record(stub: stub) }
    guard let url = URL(string: "https://\(host)") else { fatalError("invalid stub host \(host)") }
    return url
  }

  static func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  static func requests(for base: URL) -> [URLRequest] {
    records.withLock { $0[base.host ?? ""]?.requests ?? [] }
  }

  static func isStopped(_ base: URL) -> Bool {
    records.withLock { $0[base.host ?? ""]?.stopped ?? false }
  }

  private static func response(_ url: URL, status: Int, headers: [String: String])
    -> HTTPURLResponse
  {
    guard
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: nil, headerFields: headers)
    else { fatalError("cannot build a stub response for \(url)") }
    return response
  }

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let host = url.host else { return }
    let stub = Self.records.withLock { records -> Stub? in
      records[host]?.requests.append(request)
      return records[host]?.stub
    }
    guard let stub else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
      return
    }
    if let target = stub.redirectTo {
      let response = Self.response(url, status: 302, headers: ["Location": target.absoluteString])
      client?.urlProtocol(
        self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
      // A delegate that refuses the redirect gets the 302 itself as the final response.
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocolDidFinishLoading(self)
      return
    }
    let response = Self.response(
      stub.respondFrom ?? url, status: stub.status, headers: stub.headers)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    for line in stub.lines {
      client?.urlProtocol(self, didLoad: Data((line + "\n").utf8))
    }
    if !stub.hold { client?.urlProtocolDidFinishLoading(self) }
  }

  override func stopLoading() {
    guard let host = request.url?.host else { return }
    Self.records.withLock { $0[host]?.stopped = true }
  }
}
