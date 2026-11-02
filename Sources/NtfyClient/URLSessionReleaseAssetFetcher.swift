import Foundation
import NtfyCore

/// `ReleaseAssetFetching` over HTTPS for the self-updater.
///
/// - Only URLs `ReleasePolicy` allows are fetched, and only redirects to such URLs are followed
///   (GitHub answers an asset URL with a redirect to its CDN). No credentials are sent.
/// - The body is capped at `maxBytes`: by the declared size first, then chunk by chunk.
/// - The file is created `0600`; a failed download leaves nothing behind.
public struct URLSessionReleaseAssetFetcher: ReleaseAssetFetching {
  private let requestTimeout: TimeInterval
  private let totalTimeout: Duration
  private let session: URLSession

  public init(
    requestTimeout: TimeInterval = 15, totalTimeout: Duration = .seconds(300),
    session: URLSession = URLSession(configuration: .ephemeral)
  ) {
    self.requestTimeout = requestTimeout
    self.totalTimeout = totalTimeout
    self.session = session
  }

  public func download(_ url: URL, to file: URL, maxBytes: Int64) async throws(NtfyError) {
    guard ReleasePolicy.isAllowed(url) else {
      throw .invalidResponse(ReleaseUpdateError.disallowedURL(url.absoluteString).message)
    }
    let request = Self.request(url, timeout: requestTimeout)
    let session = session
    do {
      try await withTimeout(totalTimeout) {
        try await Self.fetch(request, on: session, limit: maxBytes, to: file)
      }
    } catch {
      try? FileManager.default.removeItem(at: file)
      if let failure = error as? NtfyError, failure == ChunkedDownload.tooLarge {
        throw .invalidResponse("the release asset is larger than \(maxBytes / 1_048_576) MB")
      }
      throw ServerResponse.error(from: error)
    }
  }

  private static func request(_ url: URL, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.setValue("ntfy-mac", forHTTPHeaderField: "User-Agent")
    return request
  }

  private static func fetch(
    _ request: URLRequest, on session: URLSession, limit: Int64, to file: URL
  ) async throws {
    guard
      FileManager.default.createFile(
        atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else { throw NtfyError.storage("cannot create \(file.lastPathComponent)") }
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try await ChunkedDownload.run(
      request, on: session, limit: limit, into: handle, followRedirect: ReleasePolicy.isAllowed)
  }
}
