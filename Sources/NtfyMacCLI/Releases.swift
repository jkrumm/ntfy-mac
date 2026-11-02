import Foundation
import NtfyCore

/// The newest published release: its tag and its assets' download URLs by file name.
struct LatestRelease: Sendable, Equatable {
  var tag: String
  var assets: [String: URL] = [:]

  /// The tag without its `v` (`2.1.0`).
  var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
}

/// The newest published release, from GitHub.
protocol ReleaseLookup: Sendable {
  func latest() async throws(NtfyError) -> LatestRelease
}

extension ReleaseLookup {
  /// The latest release tag, as published (`v2.1.0`).
  func latestTag() async throws(NtfyError) -> String { try await latest().tag }
}

private struct ReleaseAsset: Decodable {
  let name: String
  let url: URL

  private enum CodingKeys: String, CodingKey {
    case name
    case url = "browser_download_url"
  }
}

private struct Release: Decodable {
  let tagName: String?
  let assets: [ReleaseAsset]?

  private enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case assets
  }
}

struct GitHubReleases: ReleaseLookup {
  static let endpoint = "https://api.github.com/repos/jkrumm/ntfy-mac/releases/latest"

  func latest() async throws(NtfyError) -> LatestRelease {
    guard let url = URL(string: Self.endpoint) else { throw .invalidResponse("bad release URL") }
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("ntfy-mac", forHTTPHeaderField: "User-Agent")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    } catch {
      throw .serverUnreachable
    }
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw .invalidResponse("GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    }
    guard let release = try? JSONDecoder().decode(Release.self, from: data),
      let tag = release.tagName, !tag.isEmpty
    else {
      throw .invalidResponse("the latest release has no tag")
    }
    let assets = (release.assets ?? []).map { ($0.name, $0.url) }
    return LatestRelease(
      tag: tag, assets: Dictionary(assets, uniquingKeysWith: { first, _ in first }))
  }
}

/// A release version: `2.0.1`, `v2.0.1`, `2.0.0-dev` (a prerelease sorts below its release).
struct SemanticVersion: Comparable, Sendable {
  let major: Int
  let minor: Int
  let patch: Int
  let isPrerelease: Bool

  init?(_ text: String) {
    let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
    let parts = trimmed.split(separator: "-", maxSplits: 1)
    guard let core = parts.first else { return nil }
    let pieces = core.split(separator: ".", omittingEmptySubsequences: false)
    let numbers = pieces.compactMap { Int($0) }
    guard pieces.count == 3, numbers.count == 3 else { return nil }
    major = numbers[0]
    minor = numbers[1]
    patch = numbers[2]
    isPrerelease = parts.count > 1
  }

  static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    return lhs.isPrerelease && !rhs.isPrerelease
  }

  /// Whether `latest` is a newer release than `current`; false when either does not parse.
  static func isNewer(_ latest: String, than current: String) -> Bool {
    guard let latest = SemanticVersion(latest), let current = SemanticVersion(current) else {
      return false
    }
    return latest > current
  }
}
