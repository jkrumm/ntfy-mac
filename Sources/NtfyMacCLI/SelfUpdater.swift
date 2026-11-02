import Foundation
import NtfyCore

/// The adapters a direct (non-Homebrew) update needs.
struct SelfUpdatePorts: Sendable {
  var assets: any ReleaseAssetFetching
  var archive: any ArchiveExtracting
  var signature: any CodeSignatureChecking
  var swapper: any BundleSwapping
  var restarter: any AppRestarting
  var quitTimeout: Duration = .seconds(10)
}

/// Replaces an installed `NtfyMac.app` with a verified release.
///
/// Download, checksum, extraction and verification all happen in a private staging directory
/// next to the bundle (same volume), so the swap is one atomic rename and a failure at any step
/// leaves the installed copy untouched. After the swap the new bundle is verified in place; if
/// that fails, the swap is undone.
struct SelfUpdater: Sendable {
  static let maxArchiveBytes: Int64 = 100 * 1024 * 1024
  static let maxChecksumBytes: Int64 = 1024 * 1024
  static let checksumFile = "SHA256SUMS"

  let ports: SelfUpdatePorts
  /// The installed `NtfyMac.app`.
  let bundle: URL

  /// Installs `release`; true when the app was running and was restarted.
  func install(_ release: LatestRelease, _ out: Output) async throws -> Bool {
    let version = release.version
    let archiveName = "ntfy-mac-\(version)-arm64.tar.gz"
    guard SemanticVersion(release.tag) != nil,
      let archiveURL = release.assets[archiveName],
      let checksumURL = release.assets[Self.checksumFile]
    else {
      throw CLIFailure.runtime(
        "update-failed", "Release \(release.tag) has no \(archiveName) and \(Self.checksumFile).")
    }
    for url in [archiveURL, checksumURL] where !ReleasePolicy.isAllowed(url) {
      throw Self.failure(.disallowedURL(url.absoluteString))
    }

    let staging = try Self.makeDirectory(
      bundle.deletingLastPathComponent().appendingPathComponent(
        ".NtfyMac-update-\(UUID().uuidString)", isDirectory: true))
    var keepStaging = false
    defer { if !keepStaging { try? FileManager.default.removeItem(at: staging) } }

    let staged = try await prepare(
      version: version, archiveName: archiveName, urls: (archiveURL, checksumURL),
      staging: staging, out)
    try ports.swapper.swap(staged, bundle)
    // The staged path now holds the previous copy; the staging directory's removal deletes it.
    let verifier = StagedBundleVerifier(signature: ports.signature)
    do {
      try await verifier.verify(bundle, version: version)
    } catch {
      do {
        try ports.swapper.swap(staged, bundle)
      } catch {
        keepStaging = true
        throw CLIFailure.runtime(
          "update-failed",
          "The new app failed verification and could not be rolled back. "
            + "The previous copy is at \(staged.path).")
      }
      throw CLIFailure.runtime(
        "update-invalid", "\(error.message) The previous version was restored.")
    }
    return await restart(out)
  }

  /// Downloads, verifies and unpacks into `staging`; returns the verified staged bundle.
  private func prepare(
    version: String, archiveName: String, urls: (archive: URL, checksums: URL), staging: URL,
    _ out: Output
  ) async throws -> URL {
    let archive = staging.appendingPathComponent("release.tar.gz")
    let checksums = staging.appendingPathComponent(Self.checksumFile)
    out.note("Downloading ntfy-mac \(version)...")
    try await ports.assets.download(urls.archive, to: archive, maxBytes: Self.maxArchiveBytes)
    try await ports.assets.download(urls.checksums, to: checksums, maxBytes: Self.maxChecksumBytes)
    do {
      let text = String(bytes: try Data(contentsOf: checksums), encoding: .utf8) ?? ""
      try ReleaseChecksums(parsing: text)
        .verify(digest: try FileDigest.sha256Hex(of: archive), of: archiveName)
      try ReleasePolicy.validate(entries: try await ports.archive.entries(of: archive))
      let payload = try Self.makeDirectory(staging.appendingPathComponent("payload"))
      try await ports.archive.extract(archive, into: payload)
      let staged = payload.appendingPathComponent(ReleasePolicy.appName)
      try await StagedBundleVerifier(signature: ports.signature).verify(staged, version: version)
      return staged
    } catch let error as ReleaseUpdateError {
      throw Self.failure(error)
    }
  }

  /// Quits the running app and opens the new one; a failure here is a warning, the update
  /// itself is done. Nothing is launched when the app was not running.
  private func restart(_ out: Output) async -> Bool {
    do {
      let wasRunning = try await ports.restarter.stopIfRunning(
        bundleIdentifier: StagedBundleVerifier.bundleIdentifier, timeout: ports.quitTimeout)
      guard wasRunning else { return false }
      try await ports.restarter.start(bundle)
      return true
    } catch {
      out.note("Updated, but the app could not be restarted. Quit and reopen it.")
      return false
    }
  }

  private static func makeDirectory(_ url: URL) throws -> URL {
    do {
      try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    } catch {
      throw NtfyError.storage("cannot create \(url.path): \(error.localizedDescription)")
    }
    return url
  }

  private static func failure(_ error: ReleaseUpdateError) -> CLIFailure {
    switch error {
    case .checksumsMalformed, .checksumsDuplicate, .checksumMissing, .checksumMismatch:
      .runtime("checksum-mismatch", error.message)
    case .disallowedURL, .unsafeArchiveEntry, .bundleInvalid:
      .runtime("update-invalid", error.message)
    }
  }
}
