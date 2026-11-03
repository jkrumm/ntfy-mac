import Foundation
import NtfyCore
import NtfyTesting
import Testing

/// Homebrew services: the label depends on the Homebrew version, so the cleanup also recognises a
/// LaunchAgent plist by the program it runs.
@Suite struct LegacyBrewServiceTests {
  @Test func aBrewServiceUnderAnyLabelIsFoundByItsProgramAndRemoved() async throws {
    let fixture = try LegacyFixture(.brew)
    defer { fixture.remove() }
    let custom = "Library/LaunchAgents/org.example.ntfy.plist"
    // The keg path, not the `opt` link: both resolve into the formula prefix.
    try fixture.write(
      fixture.launchAgentPlist(
        label: "org.example.ntfy",
        program: fixture.prefix.appendingPathComponent("Cellar/ntfy-mac/1.11.0/bin/ntfy-mac").path
      ),
      to: fixture.home.appendingPathComponent(custom))
    let agents = InMemoryLaunchAgents(loaded: ["sh.brew.ntfy-mac", "org.example.ntfy"])

    let report = await fixture.cleanup(agents: agents).run()

    #expect(report.failed.isEmpty)
    #expect(
      report.removed.contains(
        "launch agent org.example.ntfy: \(fixture.home.appendingPathComponent(custom).path)"))
    #expect(agents.bootouts.sorted() == ["org.example.ntfy", "sh.brew.ntfy-mac"])
    #expect(!fixture.exists(custom))
    #expect(!fixture.exists("Library/LaunchAgents/sh.brew.ntfy-mac.plist"))
  }

  @Test func aPlistThatIsNotNtfyMacsIsLeftAlone() async throws {
    let fixture = try LegacyFixture(.brew)
    defer { fixture.remove() }
    let unrelated: [(String, String)] = [
      ("com.example.other.plist", "/opt/homebrew/opt/other/bin/ntfy-mac"),
      ("com.example.sibling.plist", fixture.optPath("ntfy-mac-extras/bin/ntfy-mac")),
      ("com.example.tool.plist", fixture.optPath("ntfy-mac/bin/other-tool")),
      ("com.example.app.plist", "/Applications/NtfyMac.app/Contents/MacOS/ntfy-mac"),
      ("com.example.relative.plist", "opt/ntfy-mac/bin/ntfy-mac"),
    ]
    for (name, program) in unrelated {
      try fixture.write(
        fixture.launchAgentPlist(label: name, program: program),
        to: fixture.home.appendingPathComponent("Library/LaunchAgents/\(name)"))
    }
    try fixture.write(
      "not a plist", to: fixture.home.appendingPathComponent("Library/LaunchAgents/broken.plist"))

    let report = await fixture.cleanup().run()

    #expect(report.failed.isEmpty)
    #expect(fixture.agents.bootouts == ["sh.brew.ntfy-mac"])
    for (name, _) in unrelated {
      #expect(fixture.exists("Library/LaunchAgents/\(name)"), "\(name)")
    }
    #expect(fixture.exists("Library/LaunchAgents/broken.plist"))
    #expect(!fixture.exists("Library/LaunchAgents/sh.brew.ntfy-mac.plist"))
  }

  @Test func bothBrewLabelsAtOnceAreRemoved() async throws {
    let fixture = try LegacyFixture(.brew)
    defer { fixture.remove() }
    let program = fixture.optPath("ntfy-mac/bin/ntfy-mac")
    try fixture.write(
      fixture.launchAgentPlist(label: LegacyInstallLayout.oldBrewLabel, program: program),
      to: fixture.home.appendingPathComponent("Library/LaunchAgents/homebrew.mxcl.ntfy-mac.plist"))
    let agents = InMemoryLaunchAgents(loaded: ["sh.brew.ntfy-mac", "homebrew.mxcl.ntfy-mac"])

    let report = await fixture.cleanup(agents: agents).run()

    #expect(report.failed.isEmpty)
    #expect(agents.bootouts.sorted() == ["homebrew.mxcl.ntfy-mac", "sh.brew.ntfy-mac"])
    #expect(!fixture.exists("Library/LaunchAgents/sh.brew.ntfy-mac.plist"))
    #expect(!fixture.exists("Library/LaunchAgents/homebrew.mxcl.ntfy-mac.plist"))
  }

  @Test func aServiceThatIsNotLoadedJustLosesItsPlist() async throws {
    let fixture = try LegacyFixture(.brew)
    defer { fixture.remove() }
    let agents = InMemoryLaunchAgents()

    let report = await fixture.cleanup(agents: agents).run()

    #expect(report.failed.isEmpty)
    #expect(agents.bootouts.isEmpty)
    #expect(!fixture.exists("Library/LaunchAgents/sh.brew.ntfy-mac.plist"))
  }

  @Test func aServiceStillLoadedWithoutItsPlistIsBootedOut() async throws {
    let fixture = try LegacyFixture(.brew)
    defer { fixture.remove() }
    try FileManager.default.removeItem(
      at: fixture.home.appendingPathComponent("Library/LaunchAgents/sh.brew.ntfy-mac.plist"))

    let report = await fixture.cleanup().run()

    #expect(report.failed.isEmpty)
    #expect(fixture.agents.bootouts == ["sh.brew.ntfy-mac"])
    #expect(await fixture.cleanup().detect().isEmpty)
  }
}
