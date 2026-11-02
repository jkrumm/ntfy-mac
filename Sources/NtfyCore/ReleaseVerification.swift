import CryptoKit
import Foundation

/// Why a downloaded release was refused. Every case means nothing was installed.
public enum ReleaseUpdateError: Error, Equatable, Sendable {
  /// `SHA256SUMS` has a line that is not `<64 hex>  <file>`.
  case checksumsMalformed(line: Int)
  case checksumsDuplicate(String)
  case checksumMissing(String)
  case checksumMismatch(String)
  /// The URL is not an https GitHub release asset.
  case disallowedURL(String)
  case unsafeArchiveEntry(String)
  case bundleInvalid(String)

  public var message: String {
    switch self {
    case .checksumsMalformed(let line): "SHA256SUMS line \(line) is malformed."
    case .checksumsDuplicate(let name): "SHA256SUMS lists \(name) more than once."
    case .checksumMissing(let name): "SHA256SUMS has no entry for \(name)."
    case .checksumMismatch(let name):
      "The SHA-256 of \(name) does not match SHA256SUMS; nothing was installed."
    case .disallowedURL(let url): "Refusing to download from \(url)."
    case .unsafeArchiveEntry(let entry): "The release archive contains an unsafe entry: \(entry)"
    case .bundleInvalid(let reason): "The downloaded app failed verification: \(reason)"
    }
  }
}

/// A parsed `SHA256SUMS` file (`shasum -a 256` output: `<64 hex>  <file name>` per line).
public struct ReleaseChecksums: Sendable, Equatable {
  private let digests: [String: String]

  /// Blank lines are ignored; anything else that is not exactly `<64 hex>␣␣<name>`, or a name
  /// that appears twice, fails the whole file.
  public init(parsing text: String) throws(ReleaseUpdateError) {
    var digests: [String: String] = [:]
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (index, line) in lines.enumerated() {
      if line.isEmpty { continue }
      let number = index + 1
      guard line.count > 66, line.dropFirst(64).hasPrefix("  ") else {
        throw .checksumsMalformed(line: number)
      }
      let digest = line.prefix(64)
      let name = String(line.dropFirst(66))
      guard digest.allSatisfy(\.isHexDigit), digest.allSatisfy(\.isASCII),
        !name.hasPrefix(" ")
      else { throw .checksumsMalformed(line: number) }
      guard digests[name] == nil else { throw .checksumsDuplicate(name) }
      digests[name] = digest.lowercased()
    }
    self.digests = digests
  }

  /// Passes only when `file` has an entry and `digest` (hex, any case) equals it.
  public func verify(digest: String, of file: String) throws(ReleaseUpdateError) {
    guard let expected = digests[file] else { throw .checksumMissing(file) }
    guard expected == digest.lowercased() else { throw .checksumMismatch(file) }
  }
}

/// SHA-256 of a file, streamed so a large archive is never held in memory.
public enum FileDigest {
  public static func sha256Hex(of file: URL) throws(NtfyError) -> String {
    do {
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      var hasher = SHA256()
      while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
      }
      return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    } catch {
      throw .storage("cannot read \(file.lastPathComponent): \(error.localizedDescription)")
    }
  }
}

/// Where a release may be downloaded from, and what an archive may unpack to.
public enum ReleasePolicy {
  /// `github.com` and the hosts GitHub redirects release assets to.
  public static let hosts: Set<String> = [
    "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
    "github-releases.githubusercontent.com",
  ]
  public static let appName = "NtfyMac.app"
  public static let licenseName = "LICENSE"

  public static func isAllowed(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(),
      hosts.contains(host), url.port == nil || url.port == 443, url.user == nil
    else { return false }
    return true
  }

  /// Rejects absolute paths, `..` components, control characters and any root entry other than
  /// `NtfyMac.app` (and below) or the `LICENSE` file. A leading `./` is tolerated.
  public static func validate(entries: [String]) throws(ReleaseUpdateError) {
    for entry in entries {
      let components = entry.split(separator: "/", omittingEmptySubsequences: true)
        .filter { $0 != "." }
      guard !entry.hasPrefix("/"), !components.contains(".."),
        !entry.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else { throw .unsafeArchiveEntry(entry) }
      guard let root = components.first else { continue }
      switch String(root) {
      case appName: break
      case licenseName where components.count == 1: break
      default: throw .unsafeArchiveEntry(entry)
      }
    }
  }
}
