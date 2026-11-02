import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct PauseCommandTests {
  @Test(arguments: [
    ("30s", 30.0), ("30m", 1800.0), ("2h", 7200.0), ("1d", 86_400.0), ("1h30m", 5400.0),
    ("90S", 90.0), ("1d12h", 129_600.0),
  ])
  func durationsParse(text: String, seconds: Double) {
    #expect(DurationParser.seconds(text) == seconds)
  }

  @Test(arguments: ["", "0m", "m", "30", "1.5h", "-5m", "5x", "h30", "1h 30m", "5 m", "tomorrow"])
  func badDurationsAreRejected(text: String) {
    #expect(DurationParser.seconds(text) == nil)
  }

  @Test func timePointsAreDurationsAgoOrISO() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(TimePoint.parse("10m", now: now) == now.addingTimeInterval(-600))
    #expect(TimePoint.parse("2023-11-14T22:13:20Z", now: now) == now)
    #expect(TimePoint.parse("2023-11-14T22:13:20.5Z", now: now)?.timeIntervalSince(now) == 0.5)
    #expect(TimePoint.parse("whenever", now: now) == nil)
  }

  @Test func pauseForWritesPausedUntilAndResumeClearsIt() async throws {
    let rig = CLIRig()
    let result = await rig.run("pause", "--for", "2h", "--json")
    #expect(result.exit == .success)
    let expected = rig.clock.now().addingTimeInterval(7200)
    #expect(await rig.config.load().pausedUntil == expected)
    let report = try result.json()
    #expect(report["paused"] as? Bool == true)
    #expect(report["indefinite"] as? Bool == false)
    #expect(report["until"] is String)

    let resumed = await rig.run("resume", "--json")
    #expect(resumed.exit == .success)
    #expect(await rig.config.load().pausedUntil == nil)
    #expect(try resumed.json()["paused"] as? Bool == false)
  }

  @Test func pauseUntilTakesAnISOTimeInTheFuture() async {
    let rig = CLIRig()
    let result = await rig.run("pause", "--until", "2030-01-01T08:00:00Z")
    #expect(result.exit == .success)
    #expect(await rig.config.load().pausedUntil == Date(timeIntervalSince1970: 1_893_484_800))
    #expect(result.stdout.contains("paused until 2030-01-01T08:00:00Z"))
    #expect(await rig.run("pause", "--until", "2001-01-01T00:00:00Z").exit == .usage)
  }

  @Test func pauseWithoutALimitIsIndefiniteAndSaysSo() async throws {
    let rig = CLIRig()
    let text = await rig.run("pause")
    #expect(text.stdout.contains("until you run: ntfy-mac resume"))
    #expect(await rig.config.load().pausedUntil == PauseWindow.indefinite)
    let json = try await rig.run("pause", "--json").json()
    #expect(json["indefinite"] as? Bool == true)
  }

  @Test func pausePreservesTheRestOfTheConfig() async {
    let rig = CLIRig()
    await rig.config.update { $0.extraTopics = ["mine"] }
    _ = await rig.run("pause", "--for", "10m")
    #expect(await rig.config.load().extraTopics == ["mine"])
    #expect(await rig.config.load().url == CLIRig.serverURL)
  }

  @Test(arguments: [
    ["pause", "--for", "soon"], ["pause", "--for", "0m"],
    ["pause", "--for", "5m", "--until", "2030-01-01T00:00:00Z"],
    ["pause", "--until", "tomorrow"], ["pause", "--for", "99999d"], ["resume", "--for", "5m"],
  ])
  func badInvocationsAreUsageErrors(arguments: [String]) async {
    let rig = CLIRig()
    #expect(await rig.run(arguments).exit == .usage, "\(arguments)")
    #expect(await rig.config.load().pausedUntil == nil)
  }

  @Test func resumeWhenNotPausedIsFine() async {
    #expect(await CLIRig().run("resume").exit == .success)
  }
}
