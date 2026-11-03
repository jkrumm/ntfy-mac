import Foundation
import Testing

@testable import NtfyMacCLI

@Suite struct MigrateCommandTests {
  private let rig = CLIRig()

  private static let leftover = "Library/LaunchAgents/sh.brew.ntfy-mac.plist"

  private func plantLeftover(_ path: String = leftover) throws {
    try rig.scratch.write("x", to: path)
  }

  @Test func aCleanHomeReportsNothingAndDoctorPasses() async throws {
    let result = await rig.run("migrate", "--json")
    #expect(result.exit == .success)
    let report = try result.json()
    #expect((report["found"] as? [String])?.isEmpty == true)
    let doctor = await rig.run("doctor", "--json")
    let checks = try #require(try doctor.json()["checks"] as? [[String: Any]])
    #expect(
      checks.first { $0["name"] as? String == "legacy-install" }?["status"] as? String == "ok")
  }

  @Test func dryRunListsAndChangesNothing() async throws {
    try plantLeftover()
    let result = await rig.run("migrate", "--dry-run", "--json")
    #expect(result.exit == .success)
    let report = try result.json()
    #expect(report["dryRun"] as? Bool == true)
    #expect((report["found"] as? [String])?.count == 1)
    #expect((report["removed"] as? [String])?.isEmpty == true)
    #expect(
      FileManager.default.fileExists(
        atPath: rig.scratch.file(Self.leftover).path))
  }

  @Test func migrateRemovesTheLeftoverAndDoctorWarnsBeforehand() async throws {
    try plantLeftover()
    let doctor = await rig.run("doctor", "--json")
    let checks = try #require(try doctor.json()["checks"] as? [[String: Any]])
    let legacy = try #require(checks.first { $0["name"] as? String == "legacy-install" })
    #expect(legacy["status"] as? String == "warn")
    #expect((legacy["detail"] as? String)?.contains("ntfy-mac migrate") == true)
    #expect(doctor.exit == .success)

    let result = await rig.run("migrate", "--json")
    #expect(result.exit == .success)
    #expect((try result.json()["removed"] as? [String])?.count == 1)
    #expect(
      !FileManager.default.fileExists(
        atPath: rig.scratch.file(Self.leftover).path))
  }

  @Test func theOlderBrewLabelIsStillMigrated() async throws {
    let older = "Library/LaunchAgents/homebrew.mxcl.ntfy-mac.plist"
    try plantLeftover(older)
    let dry = await rig.run("migrate", "--dry-run", "--json")
    let found = try #require(try dry.json()["found"] as? [String])
    #expect(found.count == 1 && found[0].hasPrefix("launch agent homebrew.mxcl.ntfy-mac:"))

    let result = await rig.run("migrate", "--json")
    #expect(result.exit == .success)
    #expect(!FileManager.default.fileExists(atPath: rig.scratch.file(older).path))
  }

  @Test func theCurrentBrewLabelIsNamedInTheOutput() async throws {
    try plantLeftover()
    let result = await rig.run("migrate", "--dry-run")
    #expect(result.stdout.contains("Would remove launch agent sh.brew.ntfy-mac:"))
  }
}
