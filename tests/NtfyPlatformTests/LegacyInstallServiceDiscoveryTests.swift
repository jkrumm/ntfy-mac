import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct LegacyInstallServiceDiscoveryTests {

  // The plist Homebrew 7 wrote on the owner's machine (service renamed to sh.brew.<name>).
  static let homebrew7Plist = """
    <?xml version="1.0" encoding="UTF-8"?>\
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\
    <plist version="1.0"><dict><key>KeepAlive</key><true/>\
    <key>Label</key><string>sh.brew.ntfy-mac</string>\
    <key>LimitLoadToSessionType</key><array><string>Aqua</string><string>Background</string>\
    <string>LoginWindow</string><string>StandardIO</string><string>System</string></array>\
    <key>ProgramArguments</key><array>\
    <string>/opt/homebrew/opt/ntfy-mac/bin/ntfy-mac</string><string>start</string></array>\
    <key>RunAtLoad</key><true/>\
    <key>StandardErrorPath</key><string>/opt/homebrew/var/log/ntfy-mac-error.log</string>\
    <key>StandardOutPath</key><string>/opt/homebrew/var/log/ntfy-mac.log</string>\
    </dict></plist>
    """

  private func plist(label: String, program: String) -> String {
    "<plist><dict><key>Label</key><string>\(label)</string>"
      + "<key>ProgramArguments</key><array><string>\(program)</string></array></dict></plist>"
  }

  private func bareHome() throws -> LegacyFixture {
    let fixture = try LegacyFixture(.curl)
    try FileManager.default.removeItem(at: fixture.home.appendingPathComponent("Library"))
    try FileManager.default.removeItem(at: fixture.state)
    try FileManager.default.removeItem(at: fixture.home.appendingPathComponent(".local/bin"))
    try FileManager.default.removeItem(at: fixture.home.appendingPathComponent("Applications"))
    return fixture
  }

  @Test func theHomebrew7ServiceIsBootedOutByItsLabelAndItsPlistRemoved() async throws {
    let fixture = try bareHome()
    defer { fixture.remove() }
    let path = "Library/LaunchAgents/sh.brew.ntfy-mac.plist"
    try fixture.write(Self.homebrew7Plist, to: fixture.home.appendingPathComponent(path))
    let agents = InMemoryLaunchAgents(loaded: ["sh.brew.ntfy-mac"])
    let cleanup = LegacyInstallCleanup(
      layout: fixture.layout, agents: agents, registry: InMemoryLaunchServices(),
      processes: InMemoryLegacyProcesses(running: [:]), runningExecutable: nil, processID: 1)

    let report = await cleanup.run()

    #expect(report.failed.isEmpty)
    #expect(report.removed.count == 1)
    #expect(agents.bootouts == ["sh.brew.ntfy-mac"])
    #expect(!fixture.exists(path))
  }

  @Test func aRenamedServiceIsFoundByItsPlistContentEvenWhenNotLoaded() async throws {
    let fixture = try bareHome()
    defer { fixture.remove() }
    let renamed = "Library/LaunchAgents/whatever.plist"
    try fixture.write(
      plist(label: "org.next.ntfy-mac", program: "/opt/homebrew/opt/ntfy-mac/bin/ntfy-mac"),
      to: fixture.home.appendingPathComponent(renamed))
    let agents = InMemoryLaunchAgents(loaded: ["org.next.ntfy-mac"])

    let loaded = LegacyInstallCleanup(
      layout: fixture.layout, agents: agents, registry: InMemoryLaunchServices(),
      processes: InMemoryLegacyProcesses(running: [:]), runningExecutable: nil, processID: 1)
    let report = await loaded.run()

    #expect(report.removed.count == 1)
    #expect(agents.bootouts == ["org.next.ntfy-mac"])
    #expect(!fixture.exists(renamed))

    try fixture.write(
      plist(label: "org.next.ntfy-mac", program: "/opt/homebrew/opt/ntfy-mac/bin/ntfy-mac"),
      to: fixture.home.appendingPathComponent(renamed))
    let quiet = InMemoryLaunchAgents()
    let notLoaded = LegacyInstallCleanup(
      layout: fixture.layout, agents: quiet, registry: InMemoryLaunchServices(),
      processes: InMemoryLegacyProcesses(running: [:]), runningExecutable: nil, processID: 1)
    _ = await notLoaded.run()
    #expect(quiet.bootouts.isEmpty)
    #expect(!fixture.exists(renamed))
  }

  @Test func unrelatedPlistsAndPlistsPointingIntoTheAppSurvive() async throws {
    let fixture = try bareHome()
    defer { fixture.remove() }
    let survivors = [
      "Library/LaunchAgents/com.example.other.plist":
        plist(label: "com.example.other", program: "/usr/bin/other"),
      "Library/LaunchAgents/com.jkrumm.ntfy-mac.app.plist": plist(
        label: "com.jkrumm.ntfy-mac.app",
        program: "/Applications/NtfyMac.app/Contents/MacOS/ntfy-mac"),
      "Library/LaunchAgents/broken.plist": "not a plist",
    ]
    for (path, text) in survivors {
      try fixture.write(text, to: fixture.home.appendingPathComponent(path))
    }
    let agents = InMemoryLaunchAgents(loaded: ["com.example.other", "com.jkrumm.ntfy-mac.app"])
    let cleanup = LegacyInstallCleanup(
      layout: fixture.layout, agents: agents, registry: InMemoryLaunchServices(),
      processes: InMemoryLegacyProcesses(running: [:]), runningExecutable: nil, processID: 1)

    let report = await cleanup.run()

    #expect(report.isEmpty)
    #expect(agents.bootouts.isEmpty)
    for path in survivors.keys { #expect(fixture.exists(path), "\(path)") }
  }

  @Test func theHomebrewServiceLogsAreRemoved() async throws {
    let fixture = try bareHome()
    defer { fixture.remove() }
    let logs = ["homebrew/var/log/ntfy-mac.log", "homebrew/var/log/ntfy-mac-error.log"]
    for log in logs { try fixture.write("x", to: fixture.home.appendingPathComponent(log)) }
    try fixture.write("x", to: fixture.home.appendingPathComponent("homebrew/var/log/other.log"))

    let report = await fixture.cleanup().run()

    #expect(report.removed.filter { $0.hasPrefix("brew service log") }.count == 2)
    for log in logs { #expect(!fixture.exists(log)) }
    #expect(fixture.exists("homebrew/var/log/other.log"))
  }
}
