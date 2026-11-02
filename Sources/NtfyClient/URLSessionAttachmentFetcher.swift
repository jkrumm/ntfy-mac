import CryptoKit
import Foundation
import NtfyCore

/// `AttachmentFetching` over HTTP, for the History window's preview.
///
/// - The bearer token goes only to the configured server's own origin, never to another host.
/// - Redirects are refused. Only `https` is fetched, plus plain `http` for the server's own origin.
/// - A host that is not the server's own must resolve to public addresses only.
/// - The body is capped at `maxBytes`: by the declared size first, then while streaming.
/// - A file lands atomically at `<directory>/<hash of the URL>/<sanitised name>` (folder `0700`,
///   file `0600`) and is reused on the next fetch. `prune` removes old folders and runs before
///   every fetch.
public struct URLSessionAttachmentFetcher: AttachmentFetching {
  public static let maxBytes: Int64 = 50 * 1024 * 1024
  /// Cached attachments not used for this long are removed by `prune`.
  public static let retention: TimeInterval = 7 * 24 * 60 * 60
  private static let maxNameLength = 100
  private static let chunkSize = 64 * 1024

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

  private static let tooLarge = NtfyError.invalidResponse("the attachment is larger than 50 MB")

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
    let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefuser())
    try check(response, limit: limit)
    let partial = try preparePartial(root: destination.root, folder: destination.folder)
    var committed = false
    let handle = try FileHandle(forWritingTo: partial)
    defer {
      try? handle.close()
      if !committed { try? FileManager.default.removeItem(at: partial) }
    }
    try await stream(bytes, into: handle, limit: limit)
    try handle.close()
    // A parallel fetch of the same attachment may have finished first; its file is as good.
    if !FileManager.default.fileExists(atPath: destination.file.path) {
      try FileManager.default.moveItem(at: partial, to: destination.file)
      committed = true
    }
  }

  /// Status and declared size, before a byte is stored.
  private static func check(_ response: URLResponse, limit: Int64) throws {
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

  /// Writes the body in chunks and stops at the cap, whatever the headers claimed.
  private static func stream(
    _ bytes: URLSession.AsyncBytes, into handle: FileHandle, limit: Int64
  ) async throws {
    var buffer = Data()
    var total: Int64 = 0
    for try await byte in bytes {
      total += 1
      guard total <= limit else { throw tooLarge }
      buffer.append(byte)
      guard buffer.count >= chunkSize else { continue }
      try handle.write(contentsOf: buffer)
      buffer.removeAll(keepingCapacity: true)
    }
    try handle.write(contentsOf: buffer)
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
