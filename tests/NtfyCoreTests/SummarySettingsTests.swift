import Foundation
import NtfyCore
import Testing

@Suite struct SummarySettingsTests {
  private func parse(_ json: String) throws -> Config {
    try #require(Config.parse(Data(json.utf8)))
  }

  @Test func theDigestIsOffByDefaultAndWritesNothing() throws {
    let config = Config()
    #expect(!config.summary.enabled)
    #expect(!config.summary.isConfigured)
    #expect(config.summary.model == "claude-haiku-5-5")
    #expect(config.summary.minAwayMinutes == 15)
    #expect(config.summary.minMessages == 3)
    #expect(config.object["summary"] == nil)
  }

  @Test func theSettingsRoundTripThroughTheFile() throws {
    var config = Config()
    config.summary = SummarySettings(
      enabled: true, endpoint: "https://gateway.example.com/anthropic", model: "haiku",
      minAwayMinutes: 30, minMessages: 5)
    let back = try parse(try #require(String(bytes: config.serialized(), encoding: .utf8)))
    #expect(back.summary == config.summary)
    #expect(back.summary.isConfigured)
  }

  @Test func onlyWhatDiffersFromTheDefaultIsWritten() throws {
    var config = Config()
    config.summary.enabled = true
    let object = try #require(config.object["summary"]?.objectValue)
    #expect(Set(object.keys) == ["enabled"])
  }

  @Test func anEnabledDigestWithoutAnEndpointIsNotConfigured() {
    #expect(!SummarySettings(enabled: true).isConfigured)
    #expect(!SummarySettings(enabled: false, endpoint: "https://x.example.com").isConfigured)
  }

  @Test func wrongTypesReadAsTheDefault() throws {
    let config = try parse(
      #"{"summary":{"enabled":"yes","endpoint":5,"model":"","minAwayMinutes":"x","minMessages":"x"}}"#
    )
    #expect(config.summary == SummarySettings())
    #expect(try parse(#"{"summary":"on"}"#).summary == SummarySettings())
  }

  @Test func theLimitsArePinned() {
    let settings = SummarySettings(minAwayMinutes: -4, minMessages: 0)
    #expect(settings.minAwayMinutes == 0)
    #expect(settings.minMessages == 1)
  }

  @Test func theKeyIsNeverInTheFile() throws {
    var config = Config()
    config.summary = SummarySettings(enabled: true, endpoint: "https://x.example.com")
    let text = try #require(String(bytes: config.serialized(), encoding: .utf8))
    #expect(!text.contains("key"))
  }

  @Test(arguments: [
    ("https://api.anthropic.com", "https://api.anthropic.com"),
    ("https://api.anthropic.com/", "https://api.anthropic.com"),
    (" https://gw.example.com/anthropic/ ", "https://gw.example.com/anthropic"),
    ("https://gw.example.com/anthropic/v1/messages", "https://gw.example.com/anthropic"),
  ]) func anEndpointIsNormalized(input: String, expected: String) {
    #expect(SummaryEndpoint.normalized(input) == expected)
  }

  @Test(arguments: ["", "api.anthropic.com", "ftp://x.example.com", "https://"])
  func somethingThatIsNoHttpAddressIsRefused(input: String) {
    #expect(SummaryEndpoint.normalized(input) == nil)
  }

  @Test func plainHttpNeedsTheOptInExceptOnLoopback() {
    #expect(SummaryEndpoint.isSecure("https://x.example.com", allowInsecure: false))
    #expect(!SummaryEndpoint.isSecure("http://x.example.com", allowInsecure: false))
    #expect(SummaryEndpoint.isSecure("http://x.example.com", allowInsecure: true))
    #expect(SummaryEndpoint.isSecure("http://127.0.0.1:8080", allowInsecure: false))
  }
}
