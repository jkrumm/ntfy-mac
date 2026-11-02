import AppKit
import Darwin
import Foundation
import NtfyCore

/// `/usr/bin/tar` for the release tarball.
public struct TarArchive: ArchiveExtracting {
  private static let executable = "/usr/bin/tar"

  public init() {}

  public func entries(of archive: URL) async throws(NtfyError) -> [String] {
    let result = try await SystemTool.run(Self.executable, ["-tzf", archive.path])
    guard result.status == 0 else { throw .storage("tar could not list the archive") }
    return try Self.parse(listing: result.output)
  }

  /// Fails closed: a listing that is not UTF-8 or has no entries is an error, never `[]`.
  static func parse(listing: Data) throws(NtfyError) -> [String] {
    guard let text = String(bytes: listing, encoding: .utf8) else {
      throw .storage("the archive listing is not valid UTF-8")
    }
    let entries = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    guard !entries.isEmpty else { throw .storage("the archive has no entries") }
    return entries
  }

  public func extract(_ archive: URL, into directory: URL) async throws(NtfyError) {
    let result = try await SystemTool.run(
      Self.executable, ["-xzf", archive.path, "-C", directory.path, "--no-same-owner"])
    guard result.status == 0 else { throw .storage("tar could not extract the archive") }
  }
}

/// `codesign --verify --deep --strict`; an ad-hoc signature passes.
public struct CodesignVerifier: CodeSignatureChecking {
  public init() {}

  public func verify(_ bundle: URL) async throws(NtfyError) {
    let result = try await SystemTool.run(
      "/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle.path])
    guard result.status == 0 else { throw .storage("codesign exited with \(result.status)") }
  }
}

/// Swaps two directories with `renamex_np(RENAME_SWAP)`, which moves both or neither. Where the
/// file system cannot, it renames the first aside, the second into its place, then the first
/// into the second's, and undoes the steps taken if one fails. That path is not atomic: if the
/// undo fails too, the error names where the previous copy is, and the caller must keep it.
public struct AtomicBundleSwapper: BundleSwapping {
  /// Returns 0 on success, else the errno.
  typealias Operation = @Sendable (_ from: String, _ to: String) -> Int32

  private let exchange: Operation
  private let rename: Operation

  public init() {
    self.init(
      exchange: { renamex_np($0, $1, UInt32(RENAME_SWAP)) == 0 ? 0 : errno },
      rename: { Darwin.rename($0, $1) == 0 ? 0 : errno })
  }

  init(exchange: @escaping Operation, rename: @escaping Operation) {
    self.exchange = exchange
    self.rename = rename
  }

  public func swap(_ first: URL, _ second: URL) throws(NtfyError) {
    let failure = exchange(first.path, second.path)
    if failure == 0 { return }
    guard failure == ENOTSUP || failure == EINVAL else { throw Self.error(failure) }
    try renameThrough(first.path, second.path)
  }

  private func renameThrough(_ first: String, _ second: String) throws(NtfyError) {
    let aside = first + ".swap-\(UUID().uuidString)"
    var failure = rename(first, aside)
    guard failure == 0 else { throw Self.error(failure) }
    failure = rename(second, first)
    guard failure == 0 else {
      _ = rename(aside, first)
      throw Self.error(failure)
    }
    failure = rename(aside, second)
    guard failure == 0 else {
      let restoredSecond = rename(first, second) == 0
      let restoredFirst = rename(aside, first) == 0
      guard restoredSecond && restoredFirst else {
        // `first` holds what `second` held and `aside` what `first` held, or what a partial
        // undo left of them.
        throw .storage(
          "cannot swap the app bundle (\(String(cString: strerror(failure)))) and could not "
            + "undo it; the copies are at \(first) and \(aside)")
      }
      throw Self.error(failure)
    }
  }

  private static func error(_ code: Int32) -> NtfyError {
    .storage("cannot swap the app bundle: \(String(cString: strerror(code)))")
  }
}

/// Quits and relaunches the app. Launching goes through `launch` (LaunchServices in
/// production), the same path the CLI uses to start the app on demand.
public struct RunningAppRestarter: AppRestarting {
  public typealias Launcher = @Sendable (URL) async -> Bool

  private let launch: Launcher

  public init(launch: @escaping Launcher) { self.launch = launch }

  public func stopIfRunning(
    bundleIdentifier: String, timeout: Duration
  ) async throws(NtfyError) -> Bool {
    let own = getpid()
    func running() -> [NSRunningApplication] {
      NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { $0.processIdentifier != own && !$0.isTerminated }
    }
    let instances = running()
    guard !instances.isEmpty else { return false }
    for instance in instances { instance.terminate() }
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !running().isEmpty {
      guard ContinuousClock.now < deadline else {
        throw .storage("the running app did not quit in time")
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return true
  }

  public func start(_ bundle: URL) async throws(NtfyError) {
    guard await launch(bundle) else { throw .appUnavailable }
  }
}
