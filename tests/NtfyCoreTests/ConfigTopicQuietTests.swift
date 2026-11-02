import Foundation
import Testing

@testable import NtfyCore

@Suite struct ConfigTopicQuietTests {
  private func parse(_ json: String) throws -> Config {
    try #require(Config.parse(Data(json.utf8)))
  }

  private func roundTrip(_ config: Config) throws -> Config {
    try #require(Config.parse(try config.serialized()))
  }

  @Test func absentKeysAreTheDefaultsAndNothingIsWritten() throws {
    let config = try parse("{}")
    #expect(config.topicSettings.isEmpty)
    #expect(config.quietHours == QuietHours())
    #expect(!config.quietHours.enabled)
    #expect(config.quietHours.start.description == "22:00")
    #expect(config.quietHours.end.description == "07:00")
    #expect(config.quietHours.urgentBypass)
    #expect(config.quietHours.digest)
    #expect(config.object.isEmpty)
  }

  @Test func topicSettingsRoundTripAndAreNotExtras() throws {
    let config = try parse(
      """
      {"topicSettings":{"alerts":{"mute":true},"build":{"minPriority":4,"emoji":"📦"}},"other":1}
      """)
    #expect(config.topicSettings["alerts"] == TopicSettings(mute: true))
    #expect(config.topicSettings["build"] == TopicSettings(minPriority: 4, emoji: "📦"))
    #expect(config.extras == ["other": .int(1)])
    #expect(try roundTrip(config) == config)
  }

  @Test func onlyNonDefaultTopicFieldsAndTopicsAreWritten() throws {
    var config = Config(topicSettings: ["a": TopicSettings(), "b": TopicSettings(emoji: "🔥")])
    let topics = try #require(config.object["topicSettings"]?.objectValue)
    #expect(topics == ["b": .object(["emoji": .string("🔥")])])
    config.topicSettings = ["a": TopicSettings()]
    #expect(config.object["topicSettings"] == nil)
  }

  @Test func malformedTopicSettingsReadAsAbsent() throws {
    let config = try parse(
      """
      {"topicSettings":{"a":5,"b":{"mute":"yes","minPriority":"high","emoji":3},
       "c":{"emoji":"  "},"d":{"minPriority":9},"e":{"minPriority":0},"f":{"minPriority":2.5}}}
      """)
    #expect(config.topicSettings["a"] == nil)
    #expect(config.topicSettings["b"] == TopicSettings())
    #expect(config.topicSettings["c"] == TopicSettings())
    #expect(config.topicSettings["d"]?.minPriority == 5)
    #expect(config.topicSettings["e"]?.minPriority == 1)
    #expect(config.topicSettings["f"]?.minPriority == nil)
    #expect(try parse(#"{"topicSettings":["x"]}"#).topicSettings.isEmpty)
  }

  @Test func oddTopicNamesRoundTrip() throws {
    let names = ["", "a/b", "ünï cödé", "🔥", "with space", "quote\"back\\slash", "../x"]
    let config = Config(
      topicSettings: Dictionary(uniqueKeysWithValues: names.map { ($0, TopicSettings(mute: true)) })
    )
    #expect(try roundTrip(config) == config)
  }

  @Test func theTopicSuppressionRule() {
    let low = Priority(clamping: 2)
    let high = Priority(clamping: 4)
    #expect(!TopicSettings().suppresses(.min))
    #expect(TopicSettings(mute: true).suppresses(.max))
    #expect(TopicSettings(minPriority: 3).suppresses(low))
    #expect(!TopicSettings(minPriority: 3).suppresses(.default))
    #expect(!TopicSettings(minPriority: 3).suppresses(high))
  }

  @Test func quietHoursRoundTripWithOnlyNonDefaultsWritten() throws {
    let config = try parse(
      #"{"quietHours":{"enabled":true,"start":"23:30","urgentBypass":false}}"#)
    #expect(config.quietHours.enabled)
    #expect(config.quietHours.start.description == "23:30")
    #expect(config.quietHours.end.description == "07:00")
    #expect(!config.quietHours.urgentBypass)
    #expect(config.quietHours.digest)
    let written = try #require(config.object["quietHours"]?.objectValue)
    #expect(Set(written.keys) == ["enabled", "start", "urgentBypass"])
    #expect(try roundTrip(config) == config)
  }

  @Test func malformedQuietHoursReadAsTheirDefaults() throws {
    let config = try parse(
      #"{"quietHours":{"enabled":"yes","start":"25:00","end":7,"urgentBypass":1,"digest":null}}"#)
    #expect(config.quietHours == QuietHours())
    #expect(try parse(#"{"quietHours":"on"}"#).quietHours == QuietHours())
  }

  @Test func quietHoursAtDefaultsAreNotWrittenAndUnknownKeysSurvive() throws {
    let config = try parse(
      #"{"quietHours":{"digest":true},"topicSettings":{},"future":{"x":[1]}}"#)
    #expect(config.object == ["future": .object(["x": .array([.int(1)])])])
    #expect(try roundTrip(config) == config)
  }
}
