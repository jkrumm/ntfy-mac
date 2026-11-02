import Foundation
import NtfyCore
import NtfyTesting
import Testing

@testable import NtfyMacCLI

/// A swap that fails after moving the installed app into the staging directory.
private struct StrandingSwapper: BundleSwapping {
  func swap(_ first: URL, _ second: URL) throws(NtfyError) {
    try? FileManager.default.moveItem(
      at: second, to: first.deletingLastPathComponent().appendingPathComponent("stranded"))
    throw .storage("cannot swap the app bundle")
  }
}

@Suite struct SelfUpdateStagingTests {
  @Test func aPrereleaseIsVerifiedAgainstTheStampedNumericCore() async throws {
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-verify-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let bundle = temp.appendingPathComponent("NtfyMac.app")
    try ReleaseFixture.writeBundle(at: bundle, version: "2.1.0", marker: "new")
    let verifier = StagedBundleVerifier(signature: ScriptedCodeSignature())

    try await verifier.verify(bundle, version: "2.1.0-rc.1")
    try await verifier.verify(bundle, version: "2.1.0")
    await #expect(throws: ReleaseUpdateError.self) {
      try await verifier.verify(bundle, version: "2.1.1-rc.1")
    }
  }

  @Test func staleStagingDirectoriesAreSweptAtTheStartOfAnUpdate() async throws {
    let rig = try SelfUpdateTests.Rig()
    let manager = FileManager.default
    let old = Date(timeIntervalSinceNow: -3600)
    func make(_ name: String, aged: Bool = true, marker: Bool = false) throws {
      let url = rig.applications.appendingPathComponent(name, isDirectory: true)
      try manager.createDirectory(at: url, withIntermediateDirectories: true)
      if marker { try Data().write(to: url.appendingPathComponent(SelfUpdater.keepMarker)) }
      if aged { try manager.setAttributes([.modificationDate: old], ofItemAtPath: url.path) }
    }
    try make(".NtfyMac-update-stale")
    try make(".NtfyMac-update-fresh", aged: false)
    try make(".NtfyMac-update-kept", marker: true)
    try make("NtfyMac-update-other")
    let file = rig.applications.appendingPathComponent(".NtfyMac-update-file")
    try Data("x".utf8).write(to: file)
    try manager.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
    let link = rig.applications.appendingPathComponent(".NtfyMac-update-link")
    try manager.createSymbolicLink(at: link, withDestinationURL: rig.installed)

    #expect(await rig.run("update").exit == .success)

    #expect(
      rig.applicationsListing == [
        ".NtfyMac-update-file", ".NtfyMac-update-fresh", ".NtfyMac-update-kept",
        ".NtfyMac-update-link", "NtfyMac-update-other", "NtfyMac.app",
      ])
    #expect(manager.fileExists(atPath: rig.installed.path))
  }

  @Test func aSwapThatStrandsTheInstalledAppKeepsItAndSaysWhere() async throws {
    var rig = try SelfUpdateTests.Rig()
    rig.cli.update?.swapper = StrandingSwapper()
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("previous copy is in"))
    let staging = try #require(rig.applicationsListing.first { $0.hasPrefix(".NtfyMac-update-") })
    let kept = rig.applications.appendingPathComponent(staging)
    #expect(manager(kept, "payload/stranded/Contents/MacOS/ntfy-mac"))
    #expect(manager(kept, SelfUpdater.keepMarker))
  }

  private func manager(_ base: URL, _ path: String) -> Bool {
    FileManager.default.fileExists(atPath: base.appendingPathComponent(path).path)
  }
}
