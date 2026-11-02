import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@testable import NtfyMacCLI

private struct NoPipeline: PipelineSource {
  func current() async -> PipelineHandles? { nil }
  func rebuilds() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private struct NoSounds: SoundListing {
  func names() -> [String] { [] }
}

@MainActor private final class SilentPreview: SoundPreviewing {
  func play(_ name: String) {}
}

private struct NoLinks: SystemSettingsOpening {
  func open(_ url: URL) async -> Bool { false }
}

private struct NoQuitGuard: QuitGuarding {
  func hold(reason: String) -> @Sendable () -> Void { {} }
}

/// The CLI reads back what the Settings model wrote: both go through the same `ConfigStore`, and
/// `config get|show` reports the values the window set.
@MainActor @Suite struct SettingsModelAgreementTests {
  private func model(
    over rig: CLIRig, tester: ScriptedServerTester = ScriptedServerTester()
  ) -> SettingsModel {
    let source = NoPipeline()
    let clock = rig.clock
    let app = AppModel(
      source: source, config: rig.config, permissions: InMemoryNotificationPermission(.allowed),
      clock: clock, configChanges: { AsyncStream { $0.finish() } })
    let flow = NotificationPermissionFlow(
      permissions: InMemoryNotificationPermission(.allowed), opener: NoLinks(),
      quitGuard: NoQuitGuard(), source: source, clock: clock)
    return SettingsModel(
      SettingsModel.Dependencies(
        config: rig.config, secrets: rig.secrets, tester: tester,
        topicSource: rig.topics, source: source, loginItem: InMemoryLoginItem(),
        sounds: NoSounds(), preview: SilentPreview(), configChanges: { AsyncStream { $0.finish() } }
      ),
      app: app, permission: flow, windows: WindowRouter())
  }

  @Test func theScalarSettingsReadBackThroughConfigGet() async throws {
    let rig = CLIRig()
    let model = model(over: rig)
    await model.setAllowInsecure(true)
    await model.setAllowPrivateNetworkActions(true)
    await model.setReAlert(false)
    await model.setReAlertInterval(seconds: 600)
    await model.setReAlertMinPriority(4)
    await model.setReAlertMaxRepeats(6)
    let expected: [String: String] = [
      "allowInsecure": "true", "allowPrivateNetworkActions": "true", "reAlert": "false",
      "reAlertIntervalSeconds": "600", "reAlertMinPriority": "4", "reAlertMaxRepeats": "6",
    ]
    #expect(Set(expected.keys) == Set(ConfigKey.allCases.map(\.rawValue)))
    for (key, value) in expected {
      let result = await rig.run("config", "get", key)
      #expect(result.stdout.contains("\(key) = \(value)"), "\(key): \(result.stdout)")
    }
  }

  @Test func topicSettingsReadBackThroughConfigTopicShow() async throws {
    let rig = CLIRig()
    let model = model(over: rig)
    await model.setMute(true, topic: "builds")
    await model.setMinPriority(4, topic: "builds")
    await model.setEmoji("🔨", topic: "builds")
    let shown = try await rig.run("config", "topic", "show", "builds", "--json").json()
    #expect(shown["mute"] as? Bool == true)
    #expect(shown["minPriority"] as? Int == 4)
    #expect(shown["emoji"] as? String == "🔨")
    _ = await model.subscribe("ops")
    let topics = await rig.run("subscribe")
    #expect(topics.stdout.contains("ops"))
    _ = await model.unsubscribe("ops")
    #expect(await rig.run("unsubscribe", "ops").exit == .runtime)
  }

  @Test func quietHoursReadBackThroughConfigQuietHoursShow() async throws {
    let rig = CLIRig()
    let model = model(over: rig)
    await model.setQuietHoursStart(try #require(ClockTime(hour: 21, minute: 30)))
    await model.setQuietHoursEnd(try #require(ClockTime(hour: 6, minute: 15)))
    await model.setQuietHoursEnabled(true)
    await model.setUrgentBypass(false)
    await model.setDigest(false)
    let shown = try await rig.run("config", "quiet-hours", "show", "--json").json()
    #expect(shown["enabled"] as? Bool == true)
    #expect(shown["start"] as? String == "21:30")
    #expect(shown["end"] as? String == "06:15")
    #expect(shown["urgentBypass"] as? Bool == false)
    #expect(shown["digest"] as? Bool == false)
  }

  @Test func soundsAndDismissReadBackThroughConfigShow() async throws {
    let rig = CLIRig()
    let model = model(over: rig)
    await model.setSound(.named("Sosumi"), for: 5)
    await model.setSound(.silent, for: 1)
    await model.setDismiss(seconds: 15, for: 3)
    await model.setDismiss(seconds: nil, for: 2)
    let sounds = try await rig.run("config", "sounds", "show", "--json").json()
    let dismiss = try await rig.run("config", "dismiss", "show", "--json").json()
    for output in [sounds, dismiss] {
      let rows = try #require(output["priorities"] as? [[String: Any]])
      func row(_ priority: Int) -> [String: Any]? {
        rows.first { $0["priority"] as? Int == priority }
      }
      #expect(row(5)?["sound"] as? String == "Sosumi")
      #expect(row(1)?["silent"] as? Bool == true)
      #expect(row(3)?["dismissSeconds"] as? Double == 15)
      #expect(row(2)?["dismissSeconds"] as? Double == 0)
    }
    await model.resetSoundsAndDismiss()
    let reset = try await rig.run("config", "sounds", "show", "--json").json()
    let defaults = try #require(reset["priorities"] as? [[String: Any]])
    #expect(
      defaults.allSatisfy {
        $0["customSound"] as? Bool == false && $0["customDismiss"] as? Bool == false
      })
  }

  @Test func theServerSaveAgreesWithSetup() async throws {
    let rig = CLIRig(configured: false)
    let model = model(over: rig, tester: ScriptedServerTester(.ok(topics: ["alerts"])))
    model.urlText = "ntfy.example.com/"
    model.tokenText = "tk_secret_value"
    await model.testAndSave()
    let setup = CLIRig(configured: false)
    _ = await setup.run("setup", "--url", "ntfy.example.com/", "--token", "tk_secret_value")
    #expect(await rig.config.load() == setup.config.load())
    #expect(await rig.secrets.token() == setup.secrets.token())
  }
}
