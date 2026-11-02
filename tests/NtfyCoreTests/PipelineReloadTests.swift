import Foundation
import Testing

@testable import NtfyCore

@Suite struct PipelineReloadTests {
  private func settings(
    url: String = "https://ntfy.example.com", token: String = "t", topics: [String]? = nil,
    extraTopics: [String] = [], sounds: [Int: ConfigSound] = [:], dismiss: [Int: Double] = [:],
    allowInsecure: Bool = false
  ) throws -> Settings {
    Settings(
      url: try #require(URL(string: url)), token: token, topics: topics,
      extraTopics: extraTopics, sounds: sounds, dismiss: dismiss, allowInsecure: allowInsecure)
  }

  @Test func nothingConfiguredStaysIdle() {
    #expect(PipelineReload.decide(current: nil, outcome: .unconfigured) == .keep)
  }

  @Test func firstConfigurationBuilds() throws {
    #expect(PipelineReload.decide(current: nil, outcome: .resolved(try settings())) == .rebuild)
  }

  @Test func removedConfigurationGoesIdle() throws {
    #expect(PipelineReload.decide(current: try settings(), outcome: .unconfigured) == .idle)
  }

  @Test func aFailedResolutionNeverTearsDownOrBuilds() throws {
    #expect(
      PipelineReload.decide(current: try settings(), outcome: .failed("half-written")) == .keep)
    #expect(PipelineReload.decide(current: nil, outcome: .failed("keychain")) == .keep)
  }

  @Test func identicalSettingsKeep() throws {
    #expect(
      PipelineReload.decide(current: try settings(), outcome: .resolved(try settings())) == .keep)
  }

  @Test func connectionChangesRebuild() throws {
    let base = try settings()
    let changed = [
      try settings(url: "https://other.example.com"),
      try settings(token: "other"),
      try settings(topics: ["a"]),
      try settings(extraTopics: ["b"]),
      try settings(allowInsecure: true),
    ]
    for new in changed {
      #expect(PipelineReload.decide(current: base, outcome: .resolved(new)) == .rebuild)
    }
  }

  @Test func perNotificationSettingsKeep() throws {
    let base = try settings()
    let changed = [
      try settings(sounds: [3: .silent]),
      try settings(dismiss: [3: 0]),
    ]
    for new in changed {
      #expect(PipelineReload.decide(current: base, outcome: .resolved(new)) == .keep)
    }
  }

  @Test func originIsSchemeHostAndExplicitPort() throws {
    #expect(try settings(url: "HTTPS://Ntfy.Example.com/base").origin == "https://ntfy.example.com")
    #expect(try settings(url: "http://192.0.2.7:8080").origin == "http://192.0.2.7:8080")
  }

  @Test func topicSelectionCarriesOverrideAndExtras() throws {
    let selection = try settings(topics: ["a"], extraTopics: ["b"]).topicSelection
    #expect(selection == TopicSelection(override: ["a"], extra: ["b"]))
  }
}
