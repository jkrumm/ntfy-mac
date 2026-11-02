import CryptoKit
import Foundation
import NtfyCore

/// `AttachmentFetching` over HTTP, for the History window's preview.
///
/// - The bearer token goes only to the configured server's own origin, never to another host.
/// - Redirects are refused. Only `https` is fetched, plus plain `http` for the server's own origin.
/// - A host that is not the server's own must resolve to public addresses only. Known residual:
///   the host is resolved once for that public-address check and again by URLSession when it
///   connects, so a DNS-rebinding answer can slip a private address in between. This is the same
///   residual as the action runner's (Wave 3); addresses are not pinned.
/// - The body is capped at `maxBytes`: by the declared size first, then chunk by chunk as it
///   arrives; a chunk that would pass the cap fails the fetch, nothing is cut short.
/// - A file lands atomically at `<directory>/<hash of the URL>/<sanitised name>` (folder `0700`,
///   file `0600`) and is reused on the next fetch. `prune` removes old folders and runs before
///   every fetch.
public struct URLSessionAttachmentFetcher: AttachmentFetching {
  public static let maxBytes: Int64 = 50 * 1024 * 1024
  /// Cached attachments not used for this long are removed by `prune`.
  public static let retention: TimeInterval = 7 * 24 * 60 * 60
  private static let maxNameLength = 100

  private let server: URL
  private let token: @Sendable () async -> String?
  private let allowInsecure: Bool
  private let limit: Int64
  private let requestTimeout: TimeInterval
  private let totalTimeout: Duration
  private let session: URLSession
  private let directory: URL
  private let resolver: any HostResolving

  /// - Parameters:
  ///   - server: the configured ntfy server; its origin is the only one that gets the token.
  ///   - token: read per fetch, so a rotated token is picked up.
  ///   - maxBytes: the size cap; only tests lower it.
  ///   - requestTimeout: how long the connection may stay silent.
  ///   - totalTimeout: the whole fetch, headers and body.
  ///   - directory: parent of the per-attachment folders.
  public init(
    server: URL,
    token: @escaping @Sendable () async -> String?,
    allowInsecure: Bool = false,
    maxBytes: Int64 = URLSessionAttachmentFetcher.maxBytes,
    requestTimeout: TimeInterval = 15,
    totalTimeout: Duration = .seconds(120),
    session: URLSession = URLSession(configuration: .ephemeral),
    directory: URL = URLSessionAttachmentFetcher.defaultDirectory(),
    resolver: any HostResolving = SystemHostResolver()
  ) {
    self.server = server
    self.token = token
    self.allowInsecure = allowInsecure
    limit = maxBytes
    self.requestTimeout = requestTimeout
    self.totalTimeout = totalTimeout
    self.session = session
    self.directory = directory
    self.resolver = resolver
  }

  /// `<Caches>/<bundle id>/attachments`.
  public static func defaultDirectory(
    bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.jkrumm.ntfy-mac"
  ) -> URL {
    let caches =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return caches.appendingPathComponent(bundleIdentifier, isDirectory: true)
      .appendingPathComponent("attachments", isDirectory: true)
  }

  public func fetch(_ attachment: MessageAttachment) async throws(NtfyError) -> URL {
    let url = attachment.url
    guard isAllowed(url) else { throw .invalidResponse("the attachment URL is not allowed") }
    if let size = attachment.size, size > limit { throw Self.tooLarge }
    guard await FetchRules.isReachable(url, server: server, resolver: resolver) else {
      throw .invalidResponse("the attachment host is on a private network")
    }
    prune()
    let folder = directory.appendingPathComponent(Self.folderName(for: url), isDirectory: true)
    let file = folder.appendingPathComponent(Self.fileName(for: attachment), isDirectory: false)
    if FileManager.default.fileExists(atPath: file.path) {
      try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: folder.path)
      return file
    }
    let request = await FetchRules.request(
      url, server: server, token: token, allowInsecure: allowInsecure, timeout: requestTimeout)
    let destination = Destination(root: directory, folder: folder, file: file)
    let (session, limit) = (session, limit)
    do {
      try await withTimeout(totalTimeout) {
        try await Self.download(request, on: session, limit: limit, to: destination)
      }
    } catch {
      Self.removeIfEmpty(folder)
      throw ServerResponse.error(from: error)
    }
    return file
  }

  /// Removes cached attachments whose folder was last used at least `age` seconds ago.
  public func prune(
    olderThan age: TimeInterval = URLSessionAttachmentFetcher.retention, now: Date = Date()
  ) {
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

  // MARK: Rules

  fileprivate static let tooLarge = NtfyError.invalidResponse("the attachment is larger than 50 MB")

  /// `https` anywhere; plain `http` only on the server's own origin.
  private func isAllowed(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), !(url.host() ?? "").isEmpty else { return false }
    if scheme == "https" { return true }
    return scheme == "http" && ServerResponse.sameOrigin(url, server)
  }

  // MARK: Names

  static func folderName(for url: URL) -> String {
    SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16)
      .map { String(format: "%02x", $0) }.joined()
  }

  /// The sender's name or the URL's last component, reduced to one safe path component: no
  /// directories, control characters or colons, no leading dots, and a bounded length that keeps
  /// the extension.
  static func fileName(for attachment: MessageAttachment) -> String {
    let raw = attachment.name ?? attachment.url.lastPathComponent
    let component =
      raw.replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/").last.map(String.init) ?? ""
    var name = String(
      component.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" })
    name = name.trimmingCharacters(in: .whitespaces)
    while name.hasPrefix(".") { name.removeFirst() }
    guard !name.isEmpty else { return "attachment" }
    guard name.count > maxNameLength else { return name }
    let fileExtension = (name as NSString).pathExtension
    let suffix = fileExtension.count <= 16 && !fileExtension.isEmpty ? ".\(fileExtension)" : ""
    return String(name.prefix(maxNameLength)) + suffix
  }

  // MARK: Download

  private struct Destination: Sendable {
    let root: URL
    let folder: URL
    let file: URL
  }

  private static func download(
    _ request: URLRequest, on session: URLSession, limit: Int64, to destination: Destination
  ) async throws {
    let partial = try preparePartial(root: destination.root, folder: destination.folder)
    var committed = false
    let handle = try FileHandle(forWritingTo: partial)
    defer {
      try? handle.close()
      if !committed { try? FileManager.default.removeItem(at: partial) }
    }
    try await ChunkedDownload.run(request, on: session, limit: limit, into: handle)
    try handle.close()
    // A parallel fetch of the same attachment may have finished first; its file is as good.
    if !FileManager.default.fileExists(atPath: destination.file.path) {
      try FileManager.default.moveItem(at: partial, to: destination.file)
      committed = true
    }
  }

  /// Status and declared size, before a byte is stored.
  fileprivate static func check(_ response: URLResponse, limit: Int64) throws {
    guard let http = response as? HTTPURLResponse else {
      throw NtfyError.invalidResponse("not an HTTP response")
    }
    switch http.statusCode {
    case 200..<300: break
    case 300..<400: throw NtfyError.redirected
    case 401, 403: throw NtfyError.unauthorized
    case 500..<600: throw NtfyError.serverUnreachable
    default: throw NtfyError.invalidResponse("HTTP \(http.statusCode)")
    }
    if let declared = Int64(http.value(forHTTPHeaderField: "Content-Length") ?? ""),
      declared > limit
    {
      throw tooLarge
    }
  }

  /// Creates the private folders and an empty `0600` file to stream into.
  private static func preparePartial(root: URL, folder: URL) throws -> URL {
    let manager = FileManager.default
    let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
    try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: attributes)
    try manager.createDirectory(
      at: folder, withIntermediateDirectories: true, attributes: attributes)
    let partial = folder.appendingPathComponent(".partial-\(UUID().uuidString)")
    guard
      manager.createFile(
        atPath: partial.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else { throw NtfyError.storage("cannot create the attachment file") }
    return partial
  }

  private static func removeIfEmpty(_ folder: URL) {
    let manager = FileManager.default
    guard (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true else { return }
    try? manager.removeItem(at: folder)
  }
}

/// Streams one request's body into a file as URLSession delivers it, in chunks rather than byte
/// by byte. The status and declared size are checked before the first chunk, redirects are
/// refused, and a chunk that would take the total past `limit` fails the download before it is
/// written.
private final class ChunkedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let handle: FileHandle
  private let limit: Int64
  private var total: Int64 = 0
  private var failure: (any Error)?
  private var continuation: CheckedContinuation<Void, any Error>?

  private init(handle: FileHandle, limit: Int64) {
    self.handle = handle
    self.limit = limit
  }

  static func run(
    _ request: URLRequest, on session: URLSession, limit: Int64, into handle: FileHandle
  ) async throws {
    let download = ChunkedDownload(handle: handle, limit: limit)
    let task = session.dataTask(with: request)
    task.delegate = download
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        download.continuation = continuation
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    do {
      try URLSessionAttachmentFetcher.check(response, limit: limit)
      completionHandler(.allow)
    } catch {
      failure = error
      completionHandler(.cancel)
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard failure == nil else { return }
    guard total + Int64(data.count) <= limit else {
      failure = URLSessionAttachmentFetcher.tooLarge
      dataTask.cancel()
      return
    }
    total += Int64(data.count)
    do {
      try handle.write(contentsOf: data)
    } catch {
      failure = error
      dataTask.cancel()
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    let outcome = failure ?? error
    if let outcome {
      continuation?.resume(throwing: outcome)
    } else {
      continuation?.resume()
    }
    continuation = nil
  }
}
