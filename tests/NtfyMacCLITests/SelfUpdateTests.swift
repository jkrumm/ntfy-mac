import CryptoKit
import Foundation
import NtfyCore
import NtfyPlatform
import NtfyTesting
import Testing

@testable import NtfyMacCLI

/// Builds a fake `NtfyMac.app` and the release tarball around it with the system `tar`.
enum ReleaseFixture {
  static func writeBundle(
    at app: URL, version: String, identifier: String = "com.jkrumm.ntfy-mac", marker: String,
    executable: Bool = true
  ) throws {
    let manager = FileManager.default
    try manager.createDirectory(
      at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let info: [String: Any] = [
      "CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: app.appendingPathComponent("Contents/Info.plist"))
    let binary = app.appendingPathComponent("Contents/MacOS/ntfy-mac")
    try Data(marker.utf8).write(to: binary)
    try manager.setAttributes(
      [.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: binary.path)
  }

  static func marker(of app: URL) -> String? {
    (try? Data(contentsOf: app.appendingPathComponent("Contents/MacOS/ntfy-mac")))
      .map { String(bytes: $0, encoding: .utf8) ?? "" }
  }

  /// A tarball with `NtfyMac.app` and `LICENSE` at its root; `tarArguments` are inserted before
  /// the file list (bsdtar `-s` rewrites and `-P` keeps absolute names for the hostile cases).
  static func tarball(
    version: String, identifier: String = "com.jkrumm.ntfy-mac", executable: Bool = true,
    extraFiles: [String] = [], tarArguments: [String] = []
  ) throws -> Data {
    let work = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-fixture-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let source = work.appendingPathComponent("src", isDirectory: true)
    try writeBundle(
      at: source.appendingPathComponent("NtfyMac.app"), version: version,
      identifier: identifier, marker: "new", executable: executable)
    try Data("license".utf8).write(to: source.appendingPathComponent("LICENSE"))
    for name in extraFiles { try Data("x".utf8).write(to: source.appendingPathComponent(name)) }
    let output = work.appendingPathComponent("release.tar.gz")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments =
      ["-czf", output.path, "-C", source.path] + tarArguments
      + ["NtfyMac.app", "LICENSE"] + extraFiles
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    return try Data(contentsOf: output)
  }

  static func hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

/// Wraps the real swapper and records each swap in the shared log.
struct LoggingSwapper: BundleSwapping {
  let log: UpdateEventLog

  func swap(_ first: URL, _ second: URL) throws(NtfyError) {
    log.append("swap")
    try AtomicBundleSwapper().swap(first, second)
  }
}

@Suite struct SelfUpdateTests {
  static let version = "9.0.0"
  static let archiveName = "ntfy-mac-9.0.0-arm64.tar.gz"
  static let archiveURL = url(
    "https://github.com/jkrumm/ntfy-mac/releases/download/v9.0.0/\(archiveName)")
  static let sumsURL = url("https://github.com/jkrumm/ntfy-mac/releases/download/v9.0.0/SHA256SUMS")

  static func url(_ text: String) -> URL {
    guard let url = URL(string: text) else { fatalError("bad test URL \(text)") }
    return url
  }

  /// A rig whose installed app is a fake old bundle, serving `tarball` as the latest release.
  struct Rig {
    var cli = CLIRig()
    let log = UpdateEventLog()
    let signature: ScriptedCodeSignature
    let fetcher: ScriptedAssetFetcher
    let applications: URL
    let installed: URL

    init(
      tarball: Data? = nil, checksum: String? = nil, running: Bool = false,
      failingSignatureCalls: Set<Int> = [], assetURL: URL = SelfUpdateTests.archiveURL,
      fetchFailure: NtfyError? = nil, stopFailure: NtfyError? = nil
    ) throws {
      let data = try tarball ?? ReleaseFixture.tarball(version: SelfUpdateTests.version)
      let digest = checksum ?? ReleaseFixture.hex(data)
      let sums = "\(digest)  \(SelfUpdateTests.archiveName)\n"
      fetcher = ScriptedAssetFetcher(
        assets: [assetURL: data, SelfUpdateTests.sumsURL: Data(sums.utf8)], failure: fetchFailure)
      signature = ScriptedCodeSignature(failingCalls: failingSignatureCalls)
      applications = cli.scratch.file("Applications")
      installed = applications.appendingPathComponent("NtfyMac.app")
      try ReleaseFixture.writeBundle(at: installed, version: "1.0.0", marker: "old")
      cli.releases = FakeReleases(
        tag: "v9.0.0",
        assets: [SelfUpdateTests.archiveName: assetURL, "SHA256SUMS": SelfUpdateTests.sumsURL])
      cli.update = SelfUpdatePorts(
        assets: fetcher, archive: TarArchive(), signature: signature,
        swapper: LoggingSwapper(log: log),
        restarter: RecordingAppRestarter(running: running, stopFailure: stopFailure, log: log))
    }

    func run(_ arguments: String...) async -> RunResult { await cli.run(arguments) }

    var applicationsListing: [String] {
      ((try? FileManager.default.contentsOfDirectory(atPath: applications.path)) ?? []).sorted()
    }
  }

  @Test func updatesTheBundleAndLeavesNoStaging() async throws {
    let rig = try Rig()
    let result = await rig.run("update", "--json")
    #expect(result.exit == .success)
    let json = try result.json()
    #expect(json["method"] as? String == "app")
    #expect(json["to"] as? String == "9.0.0")
    #expect(json["updated"] as? Bool == true)
    #expect(json["restarted"] as? Bool == false)
    #expect(ReleaseFixture.marker(of: rig.installed) == "new")
    #expect(rig.applicationsListing == ["NtfyMac.app"])
    #expect(rig.log.events == ["swap", "stop-if-running"])
    #expect(rig.signature.callCount == 2)
    #expect(rig.fetcher.requests == [Self.archiveURL, Self.sumsURL])
  }

  @Test func aRunningAppIsStoppedAfterTheSwapThenLaunched() async throws {
    let rig = try Rig(running: true)
    let result = await rig.run("update", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["restarted"] as? Bool == true)
    #expect(rig.log.events == ["swap", "stop-if-running", "start"])
  }

  @Test func anAppThatWillNotQuitIsAWarningNotAFailure() async throws {
    let rig = try Rig(running: true, stopFailure: .storage("did not quit"))
    let result = await rig.run("update", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["restarted"] as? Bool == false)
    #expect(result.stderr.contains("could not be restarted"))
    #expect(rig.log.events == ["swap", "stop-if-running"])
    #expect(ReleaseFixture.marker(of: rig.installed) == "new")
  }

  @Test func aBundleThatFailsVerificationAfterTheSwapIsRolledBack() async throws {
    let rig = try Rig(running: true, failingSignatureCalls: [2])
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("previous version was restored"))
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
    #expect(rig.log.events == ["swap", "swap"])
    #expect(rig.applicationsListing == ["NtfyMac.app"])
  }

  @Test func aFailedSignatureBeforeTheSwapInstallsNothing() async throws {
    let rig = try Rig(failingSignatureCalls: [1])
    let result = await rig.run("update", "--json")
    #expect(result.exit == .runtime)
    #expect(try result.json()["error"] != nil)
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
    #expect(rig.log.events.isEmpty)
    #expect(rig.applicationsListing == ["NtfyMac.app"])
  }

  @Test func aChecksumMismatchInstallsNothing() async throws {
    let rig = try Rig(checksum: String(repeating: "0", count: 64))
    let result = await rig.run("update", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "checksum-mismatch")
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
    #expect(rig.log.events.isEmpty)
    #expect(rig.applicationsListing == ["NtfyMac.app"])
  }

  @Test func anUppercaseChecksumIsAccepted() async throws {
    let data = try ReleaseFixture.tarball(version: Self.version)
    let rig = try Rig(tarball: data, checksum: ReleaseFixture.hex(data).uppercased())
    #expect(await rig.run("update").exit == .success)
    #expect(ReleaseFixture.marker(of: rig.installed) == "new")
  }

  @Test(arguments: [
    ["-s", "|^LICENSE$|../evil|"],
    ["-P", "-s", "|^LICENSE$|/tmp/ntfy-mac-evil-entry|"],
  ])
  func maliciousArchiveEntriesAreRejected(tarArguments: [String]) async throws {
    let rig = try Rig(
      tarball: ReleaseFixture.tarball(version: Self.version, tarArguments: tarArguments))
    let result = await rig.run("update", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "update-invalid")
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
    #expect(rig.applicationsListing == ["NtfyMac.app"])
    #expect(!FileManager.default.fileExists(atPath: "/tmp/ntfy-mac-evil-entry"))
  }

  @Test func anUnexpectedRootEntryIsRejected() async throws {
    let rig = try Rig(
      tarball: ReleaseFixture.tarball(version: Self.version, extraFiles: ["payload.sh"]))
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("unsafe entry"))
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
  }

  @Test func aWrongBundleIdentifierIsRejected() async throws {
    let rig = try Rig(
      tarball: ReleaseFixture.tarball(version: Self.version, identifier: "com.example.other"))
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("bundle identifier"))
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
  }

  @Test func aBundleOfAnotherVersionIsRejected() async throws {
    let rig = try Rig(tarball: ReleaseFixture.tarball(version: "9.0.1"))
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("version is not 9.0.0"))
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
  }

  @Test func aNonExecutableBinaryIsRejected() async throws {
    let rig = try Rig(tarball: ReleaseFixture.tarball(version: Self.version, executable: false))
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("not executable"))
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
  }

  @Test func anAssetOutsideGitHubIsNeverFetched() async throws {
    let rig = try Rig(assetURL: Self.url("https://evil.example/\(Self.archiveName)"))
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("Refusing to download"))
    #expect(rig.fetcher.requests.isEmpty)
  }

  @Test func aReleaseWithoutTheAssetsIsAnError() async throws {
    var rig = try Rig()
    rig.cli.releases = FakeReleases(tag: "v9.0.0")
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains(Self.archiveName))
  }

  @Test func anUnreachableDownloadExitsSeven() async throws {
    let rig = try Rig(fetchFailure: .serverUnreachable)
    #expect(await rig.run("update").exit == .serverUnreachable)
    #expect(rig.applicationsListing == ["NtfyMac.app"])
  }

  @Test func nothingNewerIsUpToDate() async throws {
    var rig = try Rig()
    rig.cli.releases = FakeReleases(tag: "v\(Version.current)")
    let result = await rig.run("update", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["updated"] as? Bool == false)
    #expect(rig.fetcher.requests.isEmpty)
    #expect(rig.log.events.isEmpty)
  }

  @Test func theEnvironmentSwitchDisablesSelfUpdate() async throws {
    var rig = try Rig()
    rig.cli.variables["NTFY_MAC_NO_SELF_UPDATE"] = "1"
    let result = await rig.run("update", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "update-disabled")
    #expect(rig.fetcher.requests.isEmpty)
  }

  @Test func anUnwritableParentNamesThePath() async throws {
    let rig = try Rig()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: rig.applications.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: rig.applications.path)
    }
    let result = await rig.run("update", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "update-not-writable")
    #expect((error["message"] as? String)?.contains(rig.applications.path) == true)
    #expect(rig.fetcher.requests.isEmpty)
  }

  @Test func aBuildOutsideAnAppBundleRefuses() async throws {
    var rig = try Rig()
    rig.cli.executablePath = rig.cli.scratch.file("build/ntfy-mac").path
    let result = await rig.run("update", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "update-unsupported")
    #expect(rig.fetcher.requests.isEmpty)
  }

  @Test func aSymlinkedExecutableUpdatesTheRealBundle() async throws {
    var rig = try Rig()
    let link = rig.cli.scratch.file("bin/ntfy-mac")
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: rig.installed.appendingPathComponent("Contents/MacOS/ntfy-mac"))
    rig.cli.executablePath = link.path
    #expect(await rig.run("update").exit == .success)
    #expect(ReleaseFixture.marker(of: rig.installed) == "new")
  }

  @Test func aBrewInstallIgnoresTheSelfUpdateSwitch() async throws {
    var rig = try Rig()
    rig.cli.executablePath = "/opt/homebrew/Cellar/ntfy-mac/2.0.0/bin/ntfy-mac"
    rig.cli.variables["NTFY_MAC_NO_SELF_UPDATE"] = "1"
    #expect(await rig.run("update").exit == .success)
    #expect(await rig.cli.processes.runs.count == 1)
    #expect(rig.fetcher.requests.isEmpty)
    #expect(ReleaseFixture.marker(of: rig.installed) == "old")
  }
}
