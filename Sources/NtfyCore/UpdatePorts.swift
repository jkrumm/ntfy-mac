import Foundation

/// Downloads one release asset into a file. The adapter refuses anything `ReleasePolicy`
/// does not allow, follows only allowed redirects, and fails past `maxBytes`.
public protocol ReleaseAssetFetching: Sendable {
  func download(_ url: URL, to file: URL, maxBytes: Int64) async throws(NtfyError)
}

/// Lists and unpacks the release tarball.
public protocol ArchiveExtracting: Sendable {
  /// Every entry path in the archive, as stored.
  func entries(of archive: URL) async throws(NtfyError) -> [String]
  /// Unpacks into an existing directory, without taking ownership from the archive.
  func extract(_ archive: URL, into directory: URL) async throws(NtfyError)
}

/// `codesign --verify --deep --strict`; throws when the bundle does not pass.
public protocol CodeSignatureChecking: Sendable {
  func verify(_ bundle: URL) async throws(NtfyError)
}

/// Exchanges two directories on one volume. Afterwards each path holds what the other held,
/// so calling it again undoes it. Either both moved or neither did.
public protocol BundleSwapping: Sendable {
  func swap(_ first: URL, _ second: URL) throws(NtfyError)
}

/// Stops and starts the menu-bar app.
public protocol AppRestarting: Sendable {
  /// Asks the app to quit and waits until it did. False when it was not running; throws when
  /// it is still running at `timeout`.
  func stopIfRunning(bundleIdentifier: String, timeout: Duration) async throws(NtfyError) -> Bool
  func start(_ bundle: URL) async throws(NtfyError)
}

/// Checks an unpacked `NtfyMac.app` before it replaces the installed one.
public struct StagedBundleVerifier: Sendable {
  public static let bundleIdentifier = "com.jkrumm.ntfy-mac"
  public static let executablePath = "Contents/MacOS/ntfy-mac"

  private let signature: any CodeSignatureChecking

  public init(signature: any CodeSignatureChecking) { self.signature = signature }

  public func verify(_ bundle: URL, version: String) async throws(ReleaseUpdateError) {
    let plist = bundle.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist),
      let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { throw .bundleInvalid("Info.plist is missing or unreadable") }
    guard info["CFBundleIdentifier"] as? String == Self.bundleIdentifier else {
      throw .bundleInvalid("unexpected bundle identifier")
    }
    guard info["CFBundleShortVersionString"] as? String == version else {
      throw .bundleInvalid("the bundle version is not \(version)")
    }
    let executable = bundle.appendingPathComponent(Self.executablePath)
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw .bundleInvalid("ntfy-mac is missing or not executable")
    }
    guard escapingLink(in: bundle) == nil else {
      throw .bundleInvalid("a symbolic link points outside the bundle")
    }
    do {
      try await signature.verify(bundle)
    } catch {
      throw .bundleInvalid("the code signature does not verify")
    }
  }

  /// The first symlink whose target leaves the bundle, if any.
  private func escapingLink(in bundle: URL) -> URL? {
    let roots = [bundle.standardizedFileURL.path, bundle.resolvingSymlinksInPath().path]
      .map { $0 + "/" }
    let entries = FileManager.default.enumerator(atPath: bundle.path)
    while let relative = entries?.nextObject() as? String {
      let link = bundle.appendingPathComponent(relative)
      guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
      else { continue }
      let resolved =
        URL(fileURLWithPath: target, relativeTo: link.deletingLastPathComponent())
        .standardizedFileURL.path
      if !roots.contains(where: { resolved.hasPrefix($0) }) { return link }
    }
    return nil
  }
}
