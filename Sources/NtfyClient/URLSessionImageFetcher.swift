import Foundation
import NtfyCore

/// `ImageFetching` over HTTP, for notification attachments and icons.
///
/// - The bearer token goes only to the configured server's own origin, never to another host.
/// - Redirects are refused (the fetch fails), the body is capped, and only JPEG, PNG and GIF
///   (by magic bytes) are kept.
/// - Each image lands in its own `0700` directory under `directory`; `cleanUp(olderThan:)`
///   removes old ones and runs before every fetch.
public struct URLSessionImageFetcher: ImageFetching {
  public static let maxBytes = 10 * 1024 * 1024
  /// Fetched images older than this are removed at the next fetch.
  public static let retention: TimeInterval = 60 * 60

  private let server: URL
  private let token: @Sendable () async -> String?
  private let allowInsecure: Bool
  private let requestTimeout: TimeInterval
  private let totalTimeout: Duration
  private let session: URLSession
  private let directory: URL
  private let resolver: any HostResolving

  /// - Parameters:
  ///   - server: the configured ntfy server; its origin is the only one that gets the token.
  ///   - token: read per fetch, so a rotated token is picked up.
  ///   - requestTimeout: how long the connection may stay silent.
  ///   - totalTimeout: the whole fetch, headers and body.
  ///   - directory: parent of the per-fetch directories.
  public init(
    server: URL,
    token: @escaping @Sendable () async -> String?,
    allowInsecure: Bool = false,
    requestTimeout: TimeInterval = 10,
    totalTimeout: Duration = .seconds(15),
    session: URLSession = URLSession(configuration: .ephemeral),
    directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ntfy-mac-images", isDirectory: true),
    resolver: any HostResolving = SystemHostResolver()
  ) {
    self.resolver = resolver
    self.server = server
    self.token = token
    self.allowInsecure = allowInsecure
    self.requestTimeout = requestTimeout
    self.totalTimeout = totalTimeout
    self.session = session
    self.directory = directory
  }

  public func fetch(_ url: URL) async -> URL? {
    guard let url = URLPolicy.imageURL(url), await isReachable(url) else { return nil }
    cleanUp(olderThan: Self.retention)
    let request = await makeRequest(url)
    let (session, directory) = (session, directory)
    let data = try? await withTimeout(totalTimeout) {
      try await Self.download(request, on: session)
    }
    guard let data, let format = ImageFormat.detect(data) else { return nil }
    return Self.store(data, format: format, in: directory)
  }

  /// Removes fetched images that are at least `age` seconds old.
  public func cleanUp(olderThan age: TimeInterval, now: Date = Date()) {
    let manager = FileManager.default
    let entries = try? manager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
    for entry in entries ?? [] {
      let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      guard let modified, now.timeIntervalSince(modified) >= age else { continue }
      try? manager.removeItem(at: entry)
    }
  }

  /// The configured server's own origin is trusted. Any other host must resolve to public
  /// addresses only, so a sender cannot make the app fetch from the local network.
  private func isReachable(_ url: URL) async -> Bool {
    if ServerResponse.sameOrigin(url, server) { return true }
    guard let host = url.host() else { return false }
    return await HostSafety.resolvesToPublicAddresses(host, using: resolver)
  }

  // MARK: Request

  private func makeRequest(_ url: URL) async -> URLRequest {
    var bearer: String?
    if ServerResponse.sameOrigin(url, server) {
      let candidate = await token()
      let allowed =
        (try? ServerEndpoint.url(
          base: server, path: "", token: candidate, allowInsecure: allowInsecure)) != nil
      bearer = allowed ? candidate : nil
    }
    return URLRequest.authorized(url, token: bearer, timeout: requestTimeout)
  }

  // MARK: Download

  private static func download(_ request: URLRequest, on session: URLSession) async throws -> Data?
  {
    let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefuser())
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      return nil
    }
    let declared = Int(http.value(forHTTPHeaderField: "Content-Length") ?? "") ?? 0
    guard declared <= maxBytes else { return nil }
    var data = Data()
    for try await byte in bytes {
      guard data.count < maxBytes else { return nil }
      data.append(byte)
    }
    return data
  }

  // MARK: Storage

  private static func store(_ data: Data, format: ImageFormat, in directory: URL) -> URL? {
    let manager = FileManager.default
    let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = folder.appendingPathComponent("image.\(format.fileExtension)")
    let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
    do {
      try manager.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: attributes)
      try manager.createDirectory(
        at: folder, withIntermediateDirectories: false, attributes: attributes)
      try data.write(to: file, options: .atomic)
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      return file
    } catch {
      try? manager.removeItem(at: folder)
      return nil
    }
  }
}
