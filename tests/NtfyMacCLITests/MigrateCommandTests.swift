import Foundation
import Testing

@testable import NtfyMacCLI

@Suite struct MigrateCommandTests {
  private let rig = CLIRig()

  private func plantLeftover() throws {
    try rig.scratch.write("x", to: "Library/LaunchAgents/homebrew.mxcl.ntfy-mac.plist")
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
        atPath: rig.scratch.file("Library/LaunchAgents/homebrew.mxcl.ntfy-mac.plist").path))
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
        atPath: rig.scratch.file("Library/LaunchAgents/homebrew.mxcl.ntfy-mac.plist").path))
  }

  private func legacyCheck() async throws -> (status: String?, result: RunResult) {
    let doctor = await rig.run("doctor", "--json")
    let checks = try #require(try doctor.json()["checks"] as? [[String: Any]])
    let legacy = checks.first { $0["name"] as? String == "legacy-install" }
    return (legacy?["status"] as? String, doctor)
  }

  @Test func doctorWarnsAboutAHomebrew1xKegButNotAFormulaKeg() async throws {
    try rig.scratch.write("x", to: "brew/Cellar/ntfy-mac/2.0.0/NtfyMac.app/Contents/MacOS/ntfy-mac")
    try rig.scratch.write("x", to: "brew/Cellar/ntfy-mac/2.0.0/bin/ntfy-mac")
    #expect(try await legacyCheck().status == "ok")

    try rig.scratch.write("x", to: "brew/Cellar/ntfy-mac/1.11.0/bin/ntfy-mac")
    let warned = try await legacyCheck()
    #expect(warned.status == "warn")
    #expect(warned.result.exit == .success)

    let migrate = await rig.run("migrate", "--json")
    #expect(migrate.exit == .success)
    #expect((try migrate.json()["failed"] as? [String])?.isEmpty == true)
  }
}
