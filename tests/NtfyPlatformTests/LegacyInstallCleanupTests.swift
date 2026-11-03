import Foundation
import NtfyCore
import NtfyPlatform
import NtfyTesting
import Testing

/// A 1.11 install on disk in a temp HOME, in its curl or brew variant, with fakes for launchd,
/// Launch Services and process inspection. Nothing here touches the real home or any system tool.
struct LegacyFixture {
  /// `brew` is Homebrew 7 (`sh.brew.ntfy-mac`), `brewOld` the older `homebrew.mxcl.ntfy-mac`.
  enum Variant { case curl, brew, brewOld }

  static let machO = Data([0xCF, 0xFA, 0xED, 0xFE, 0, 0, 0, 0])

  let home: URL
  let variant: Variant
  let daemonPID: Int32 = 4242
  let agents: InMemoryLaunchAgents
  let registry: InMemoryLaunchServices
  let processes: InMemoryLegacyProcesses

  var state: URL { home.appendingPathComponent(".local/share/ntfy-mac") }
  var prefix: URL { home.appendingPathComponent("homebrew") }
  var kegHelper: URL {
    prefix.appendingPathComponent("Cellar/ntfy-mac/1.11.0/libexec/ntfy-notify.app")
  }
  var layout: LegacyInstallLayout {
    LegacyInstallLayout(home: home, uid: 501, brewPrefixes: [prefix])
  }

  init(
    _ variant: Variant, failingLabels: Set<String> = [], failingPaths: Set<String> = []
  ) throws {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-legacy-\(UUID().uuidString)", isDirectory: true)
    let prefix = home.appendingPathComponent("homebrew")
    self.home = home
    self.variant = variant
    let label = variant.label
    let binary =
      variant == .curl
      ? home.appendingPathComponent(".local/bin/ntfy-mac")
      : prefix.appendingPathComponent("Cellar/ntfy-mac/1.11.0/bin/ntfy-mac")
    let helpers =
      variant == .curl
      ? [
        home.appendingPathComponent(".local/share/ntfy-mac/ntfy-notify.app").path,
        home.appendingPathComponent("Applications/ntfy-notify.app").path,
      ] : [prefix.appendingPathComponent("Cellar/ntfy-mac/1.11.0/libexec/ntfy-notify.app").path]
    agents = InMemoryLaunchAgents(loaded: [label], failing: failingLabels)
    registry = InMemoryLaunchServices(
      registered: helpers + ["/Volumes/Old/ntfy-notify.app"], failing: failingPaths)
    processes = InMemoryLegacyProcesses(running: [4242: binary.path])
    try build(label: label, binary: binary)
  }

  func optPath(_ relative: String) -> String {
    prefix.appendingPathComponent("opt/\(relative)").path
  }

  /// A LaunchAgent plist as Homebrew writes it for a `service` block with `keep_alive`.
  func launchAgentPlist(label: String, program: String) -> String {
    let lines = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<plist version=\"1.0\">", "<dict>",
      "<key>KeepAlive</key>", "<true/>", "<key>Label</key>", "<string>\(label)</string>",
      "<key>ProgramArguments</key>", "<array>", "<string>\(program)</string>",
      "<string>start</string>", "</array>", "<key>RunAtLoad</key>", "<true/>", "</dict>",
      "</plist>",
    ]
    return lines.joined(separator: "\n")
  }

  private func build(label: String, binary: URL) throws {
    let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    let program = variant == .curl ? binary.path : optPath("ntfy-mac/bin/ntfy-mac")
    try write(launchAgentPlist(label: label, program: program), to: plist)
    try write(
      "{\"url\":\"https://ntfy.test\"}",
      to: home.appendingPathComponent(".config/ntfy-mac/config.json"))
    try write("{\"lastMessageId\":\"abc\"}", to: state.appendingPathComponent("state.json"))
    for name in ["ntfy-mac.log", "ntfy-mac-error.log", "state.json.tmp", "ntfy-mac.tmp"] {
      try write("x", to: state.appendingPathComponent(name))
    }
    try write("\(daemonPID)\n", to: state.appendingPathComponent("ntfy-mac.pid"))
    try write("x", to: state.appendingPathComponent(".state.json.UUID.tmp"))
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Self.machO.write(to: binary)
    switch variant {
    case .curl:
      for helper in [
        state.appendingPathComponent("ntfy-notify.app"),
        home.appendingPathComponent("Applications/ntfy-notify.app"),
      ] {
        try write("x", to: helper.appendingPathComponent("Contents/MacOS/ntfy-notify"))
      }
    case .brew, .brewOld:
      try write("x", to: kegHelper.appendingPathComponent("Contents/MacOS/ntfy-notify"))
      let opt = prefix.appendingPathComponent("opt")
      try FileManager.default.createDirectory(at: opt, withIntermediateDirectories: true)
      try FileManager.default.createSymbolicLink(
        at: opt.appendingPathComponent("ntfy-mac"),
        withDestinationURL: prefix.appendingPathComponent("Cellar/ntfy-mac/1.11.0"))
    }
  }

  func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }

  func cleanup(
    agents: InMemoryLaunchAgents? = nil, runningExecutable: URL? = nil, processID: Int32 = 1
  ) -> LegacyInstallCleanup {
    LegacyInstallCleanup(
      layout: layout, agents: agents ?? self.agents, registry: registry, processes: processes,
      plists: LaunchAgentPlistFiles(), runningExecutable: runningExecutable, processID: processID)
  }

  func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: home.appendingPathComponent(path).path)
  }

  func remove() { try? FileManager.default.removeItem(at: home) }

  /// The titles the cleanup is expected to report, in order.
  var expected: [String] {
    func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }
    let logs = ["ntfy-mac.log", "ntfy-mac-error.log"].map {
      "log: \(path(".local/share/ntfy-mac/\($0)"))"
    }
    let temporary = ["ntfy-mac.tmp", "state.json.tmp"].map {
      "temporary file: \(path(".local/share/ntfy-mac/\($0)"))"
    }
    switch variant {
    case .curl:
      return [
        "launch agent com.jkrumm.ntfy-mac: \(path("Library/LaunchAgents/com.jkrumm.ntfy-mac.plist"))",
        "1.x daemon: pid 4242",
        "curl helper app: \(path(".local/share/ntfy-mac/ntfy-notify.app"))",
        "dev helper app: \(path("Applications/ntfy-notify.app"))",
        "curl binary: \(path(".local/bin/ntfy-mac"))",
      ] + logs + temporary
        + [
          "Launch Services entry: \(path(".local/share/ntfy-mac/ntfy-notify.app"))",
          "Launch Services entry: \(path("Applications/ntfy-notify.app"))",
          "Launch Services entry: /Volumes/Old/ntfy-notify.app",
        ].sorted()
    case .brew, .brewOld:
      return [
        "launch agent \(variant.label): \(path("Library/LaunchAgents/\(variant.label).plist"))",
        "1.x daemon: pid 4242",
        "brew helper app: \(kegHelper.path)",
      ] + logs + temporary
        + [
          "Launch Services entry: \(kegHelper.path)",
          "Launch Services entry: /Volumes/Old/ntfy-notify.app",
        ].sorted()
    }
  }
}

extension LegacyFixture.Variant {
  var label: String {
    switch self {
    case .curl: LegacyInstallLayout.curlLabel
    case .brew: LegacyInstallLayout.brewLabel
    case .brewOld: LegacyInstallLayout.oldBrewLabel
    }
  }
}

@Suite struct LegacyInstallCleanupTests {
  @Test(arguments: [LegacyFixture.Variant.curl, .brew, .brewOld])
  func removesExactlyTheLegacyArtifacts(variant: LegacyFixture.Variant) async throws {
    let fixture = try LegacyFixture(variant)
    defer { fixture.remove() }

    let report = await fixture.cleanup().run()

    #expect(report.failed.isEmpty)
    #expect(report.found == fixture.expected)
    #expect(report.removed == fixture.expected)
    #expect(fixture.agents.bootouts == [variant.label])
    #expect(fixture.processes.terminated == [4242])
    #expect(fixture.registry.unregistered.count == (variant == .curl ? 3 : 2))
    for gone in [
      "Library/LaunchAgents/com.jkrumm.ntfy-mac.plist",
      "Library/LaunchAgents/sh.brew.ntfy-mac.plist",
      "Library/LaunchAgents/homebrew.mxcl.ntfy-mac.plist",
      ".local/bin/ntfy-mac", ".local/share/ntfy-mac/ntfy-mac.log",
      ".local/share/ntfy-mac/ntfy-mac-error.log", ".local/share/ntfy-mac/ntfy-mac.pid",
      ".local/share/ntfy-mac/state.json.tmp", ".local/share/ntfy-mac/ntfy-notify.app",
      "Applications/ntfy-notify.app", "homebrew/Cellar/ntfy-mac/1.11.0/libexec/ntfy-notify.app",
    ] {
      #expect(!fixture.exists(gone), "\(gone)")
    }
    // The user's data and 2.0's own hidden temp files stay.
    #expect(fixture.exists(".config/ntfy-mac/config.json"))
    #expect(fixture.exists(".local/share/ntfy-mac/state.json"))
    #expect(fixture.exists(".local/share/ntfy-mac/.state.json.UUID.tmp"))
  }

  @Test(arguments: [LegacyFixture.Variant.curl, .brew, .brewOld])
  func aSecondRunFindsAndRemovesNothing(variant: LegacyFixture.Variant) async throws {
    let fixture = try LegacyFixture(variant)
    defer { fixture.remove() }
    let cleanup = fixture.cleanup()
    _ = await cleanup.run()

    let again = await cleanup.run()

    #expect(again.isEmpty)
    #expect(fixture.agents.bootouts.count == 1)
    #expect(fixture.processes.terminated == [4242])
    #expect(await cleanup.detect().isEmpty)
  }

  @Test(arguments: [LegacyFixture.Variant.curl, .brew, .brewOld])
  func detectListsEverythingAndChangesNothing(variant: LegacyFixture.Variant) async throws {
    let fixture = try LegacyFixture(variant)
    defer { fixture.remove() }

    let report = await fixture.cleanup().detect()

    #expect(report.found == fixture.expected)
    #expect(report.removed.isEmpty && report.failed.isEmpty)
    #expect(fixture.agents.bootouts.isEmpty)
    #expect(fixture.processes.terminated.isEmpty)
    #expect(fixture.registry.unregistered.isEmpty)
    #expect(fixture.exists(".local/bin/ntfy-mac") || variant != .curl)
    #expect(fixture.exists("Library/LaunchAgents/\(variant.label).plist"))
    #expect(fixture.exists("homebrew/Cellar/ntfy-mac/1.11.0/bin/ntfy-mac") || variant == .curl)
  }

  @Test func quickScopeSkipsTheLaunchServicesScan() async throws {
    let fixture = try LegacyFixture(.curl)
    defer { fixture.remove() }

    let report = await fixture.cleanup().detect(scope: .quick)

    #expect(!report.found.isEmpty)
    #expect(report.found.allSatisfy { !$0.hasPrefix("Launch Services") })
  }

  @Test func aSymlinkedBinaryAndTheRunningExecutableSurvive() async throws {
    let fixture = try LegacyFixture(.curl)
    defer { fixture.remove() }
    let binary = fixture.home.appendingPathComponent(".local/bin/ntfy-mac")
    let app = fixture.home.appendingPathComponent("NtfyMac.app/Contents/MacOS/ntfy-mac")
    try fixture.write("x", to: app)
    try FileManager.default.removeItem(at: binary)
    try FileManager.default.createSymbolicLink(at: binary, withDestinationURL: app)

    let report = await fixture.cleanup().run()

    #expect(!report.found.contains { $0.hasPrefix("curl binary") })
    #expect(fixture.exists("NtfyMac.app/Contents/MacOS/ntfy-mac"))
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: binary.path)) == app.path)

    let running = try LegacyFixture(.curl)
    defer { running.remove() }
    let own = running.home.appendingPathComponent(".local/bin/ntfy-mac")
    let second = await running.cleanup(runningExecutable: own).run()
    #expect(!second.found.contains { $0.hasPrefix("curl binary") })
    #expect(running.exists(".local/bin/ntfy-mac"))
  }

  @Test func aScriptAtTheBinaryPathIsNotRemoved() async throws {
    let fixture = try LegacyFixture(.curl)
    defer { fixture.remove() }
    try fixture.write("#!/bin/sh\n", to: fixture.home.appendingPathComponent(".local/bin/ntfy-mac"))

    _ = await fixture.cleanup().run()

    #expect(fixture.exists(".local/bin/ntfy-mac"))
  }

  @Test func neverSignalsAnUnrelatedProcessTheNewAppOrItself() async throws {
    for executable in [
      "/usr/bin/some-other-tool", "/Applications/NtfyMac.app/Contents/MacOS/ntfy-mac",
      "/Applications/NtfyMac.app/Contents/MacOS/NtfyMac",
    ] {
      let fixture = try LegacyFixture(.curl)
      defer { fixture.remove() }
      let processes = InMemoryLegacyProcesses(running: [4242: executable])
      let cleanup = LegacyInstallCleanup(
        layout: fixture.layout, agents: fixture.agents, registry: fixture.registry,
        processes: processes, runningExecutable: nil, processID: 1)

      let report = await cleanup.run()

      #expect(processes.terminated.isEmpty, "\(executable)")
      #expect(!report.found.contains("1.x daemon: pid 4242"))
    }

    let fixture = try LegacyFixture(.curl)
    defer { fixture.remove() }
    let own = fixture.cleanup(processID: fixture.daemonPID)
    _ = await own.run()
    #expect(fixture.processes.terminated.isEmpty)
  }

  @Test func aDaemonThatSurvivesKillIsReportedAsFailed() async throws {
    let fixture = try LegacyFixture(.curl)
    defer { fixture.remove() }
    let binary = fixture.home.appendingPathComponent(".local/bin/ntfy-mac").path
    let stubborn = InMemoryLegacyProcesses(running: [4242: binary], surviving: [4242])
    let cleanup = LegacyInstallCleanup(
      layout: fixture.layout, agents: fixture.agents, registry: fixture.registry,
      processes: stubborn, runningExecutable: nil, processID: 1)

    let report = await cleanup.run()

    #expect(stubborn.terminated == [4242])
    #expect(report.failed.contains { $0.hasPrefix("1.x daemon: pid 4242") })
  }

  @Test func aReusedPidIsNotTerminated() throws {
    let processes = InMemoryLegacyProcesses(running: [4242: "/usr/bin/other"])
    try processes.terminate(4242, expectedPath: "/old/ntfy-mac")
    #expect(processes.terminated.isEmpty)
    #expect(processes.executablePath(of: 4242) == "/usr/bin/other")
  }

  @Test func aFailingStepLandsInFailedAndTheRestStillRuns() async throws {
    let helper = "/Volumes/Old/ntfy-notify.app"
    let fixture = try LegacyFixture(
      .curl, failingLabels: [LegacyInstallLayout.curlLabel], failingPaths: [helper])
    defer { fixture.remove() }

    let report = await fixture.cleanup().run()

    #expect(report.failed.count == 2)
    #expect(report.failed.contains { $0.hasPrefix("launch agent com.jkrumm.ntfy-mac") })
    #expect(report.failed.contains { $0.hasPrefix("Launch Services entry: \(helper)") })
    #expect(report.removed.count == fixture.expected.count - 2)
    // The plist stays, so a later run can still stop the service.
    #expect(fixture.exists("Library/LaunchAgents/com.jkrumm.ntfy-mac.plist"))
    #expect(!fixture.exists(".local/bin/ntfy-mac"))
    #expect(!fixture.exists(".local/share/ntfy-mac/ntfy-notify.app"))
    #expect(fixture.processes.terminated == [4242])
    #expect(fixture.exists(".local/share/ntfy-mac/state.json"))
  }

  @Test func aFailedLaunchServicesScanIsReportedAndFilesAreStillRemoved() async throws {
    let fixture = try LegacyFixture(.curl)
    defer { fixture.remove() }
    let cleanup = LegacyInstallCleanup(
      layout: fixture.layout, agents: fixture.agents,
      registry: InMemoryLaunchServices(scanFails: true), processes: fixture.processes,
      runningExecutable: nil, processID: 1)

    let report = await cleanup.run()

    #expect(report.failed.count == 1)
    #expect(report.failed.first?.hasPrefix("Launch Services scan") == true)
    #expect(!fixture.exists(".local/bin/ntfy-mac"))
  }
}
