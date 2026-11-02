import Foundation
import Testing

@testable import NtfyCore

@Suite struct ConfigTests {
  private func parse(_ json: String) -> Config? { Config.parse(Data(json.utf8)) }

  @Test func readsTheDocumentedShape() throws {
    let config = try #require(
      parse(
        """
        {"url":"https://ntfy.example.com","token":"tk","sounds":{"1":"Ping","5":null},
         "dismiss":{"3":30,"4":0},"extraTopics":["a","b"]}
        """))
    #expect(config.url == "https://ntfy.example.com")
    #expect(config.token == "tk")
    #expect(config.sounds == [1: .named("Ping"), 5: .silent])
    #expect(config.dismiss == [3: 30, 4: 0])
    #expect(config.extraTopics == ["a", "b"])
    #expect(config.extras.isEmpty)
  }

  @Test func unknownKeysSurviveARoundTrip() throws {
    let config = try #require(
      parse(
        """
        {"url":"https://x.example.com","future":{"nested":[1,2.5,true,null,"s"]},"n":7}
        """))
    let again = try #require(Config.parse(try config.serialized()))
    #expect(again == config)
    #expect(again.extras["n"] == .int(7))
    #expect(
      again.extras["future"]
        == .object(["nested": .array([.int(1), .double(2.5), .bool(true), .null, .string("s")])]))
  }

  @Test func writesPrettyJSONWithATrailingNewlineAndNoEscapedSlashes() throws {
    let config = Config(url: "https://x.example.com", dismiss: [3: 30])
    let text = String(bytes: try config.serialized(), encoding: .utf8) ?? ""
    #expect(text.hasSuffix("}\n"))
    #expect(text.contains("\n  \"url\""))
    #expect(text.contains("https://x.example.com"))
    #expect(text.contains(": 30\n"))
  }

  @Test func emptyFieldsAreOmittedSoResetRemovesTheKey() throws {
    var config = try #require(
      parse(#"{"sounds":{"1":"Ping"},"dismiss":{"1":5},"extraTopics":["a"]}"#))
    config.sounds = [:]
    config.dismiss = [:]
    config.extraTopics = []
    #expect(String(bytes: try config.serialized(), encoding: .utf8) ?? "" == "{\n\n}\n")
  }

  @Test func wrongTypedKnownKeysReadAsAbsent() throws {
    let config = try #require(
      parse(
        """
        {"url":5,"token":["x"],"sounds":{"1":3,"2":"Pop","9":"Glass","x":"Glass"},
         "dismiss":{"1":"soon","2":10.5,"0":3},"extraTopics":["a",1,"b"]}
        """))
    #expect(config.url == nil)
    #expect(config.token == nil)
    #expect(config.sounds == [2: .named("Pop")])
    #expect(config.dismiss == [2: 10.5])
    #expect(config.extraTopics == ["a", "b"])
  }

  @Test(arguments: ["", "   ", "not json", "[1,2]", "\"str\"", "{\"url\":"])
  func malformedOrNonObjectContentDoesNotParse(content: String) {
    #expect(parse(content) == nil)
  }

  @Test func fractionalDismissKeepsItsValue() throws {
    let config = Config(dismiss: [1: 2.5, 2: 4])
    let again = try #require(Config.parse(try config.serialized()))
    #expect(again.dismiss == [1: 2.5, 2: 4])
  }

  @Test func allowInsecureDefaultsToFalseAndIsNotWrittenWhenOff() throws {
    let config = try #require(parse(#"{"url":"http://n.example.com"}"#))
    #expect(config.allowInsecure == false)
    #expect(config.object["allowInsecure"] == nil)
  }

  @Test func allowInsecureRoundTripsAndIsNotAnExtra() throws {
    let config = try #require(parse(#"{"allowInsecure":true,"other":1}"#))
    #expect(config.allowInsecure)
    #expect(config.extras == ["other": .int(1)])
    let again = try #require(Config.parse(try config.serialized()))
    #expect(again.allowInsecure)
    #expect(again == config)
  }

  @Test func wrongTypedAllowInsecureReadsAsFalse() throws {
    #expect(try #require(parse(#"{"allowInsecure":"yes"}"#)).allowInsecure == false)
  }

  @Test func deliveryKeysDefaultAndAreNotWrittenAtDefaults() throws {
    let config = try #require(parse("{}"))
    #expect(config.allowPrivateNetworkActions == false)
    #expect(config.reAlert)
    #expect(config.reAlertIntervalSeconds == 300)
    #expect(config.reAlertMinPriority == 5)
    #expect(config.reAlertMaxRepeats == 12)
    #expect(config.object.isEmpty)
  }

  @Test func deliveryKeysRoundTripAndAreNotExtras() throws {
    let config = try #require(
      parse(
        """
        {"allowPrivateNetworkActions":true,"reAlert":false,"reAlertIntervalSeconds":60,
         "reAlertMinPriority":4,"reAlertMaxRepeats":0,"other":1}
        """))
    #expect(config.allowPrivateNetworkActions)
    #expect(config.reAlert == false)
    #expect(config.reAlertIntervalSeconds == 60)
    #expect(config.reAlertMinPriority == 4)
    #expect(config.reAlertMaxRepeats == 0)
    #expect(config.extras == ["other": .int(1)])
    #expect(try #require(Config.parse(try config.serialized())) == config)
  }

  @Test func reAlertMinPriorityIsClamped() throws {
    #expect(try #require(parse(#"{"reAlertMinPriority":9}"#)).reAlertMinPriority == 5)
    #expect(try #require(parse(#"{"reAlertMinPriority":-2}"#)).reAlertMinPriority == 1)
    #expect(Config(reAlertMinPriority: 0).reAlertMinPriority == 1)
  }

  @Test func wrongTypedDeliveryKeysFallBackToDefaults() throws {
    let config = try #require(
      parse(
        """
        {"allowPrivateNetworkActions":"yes","reAlert":"no","reAlertIntervalSeconds":"5",
         "reAlertMinPriority":2.5,"reAlertMaxRepeats":-1}
        """))
    #expect(config.allowPrivateNetworkActions == false)
    #expect(config.reAlert)
    #expect(config.reAlertIntervalSeconds == 300)
    #expect(config.reAlertMinPriority == 5)
    #expect(config.reAlertMaxRepeats == 12)
  }

  @Test func pausedUntilIsAbsentByDefaultAndNotWritten() throws {
    let config = try #require(parse("{}"))
    #expect(config.pausedUntil == nil)
    #expect(config.object["pausedUntil"] == nil)
  }

  @Test func pausedUntilRoundTripsAsISO8601AndIsNotAnExtra() throws {
    let config = try #require(parse(#"{"pausedUntil":"2026-11-02T10:00:00Z","other":1}"#))
    #expect(config.pausedUntil == Date(timeIntervalSince1970: 1_793_613_600))
    #expect(config.extras == ["other": .int(1)])
    let again = try #require(Config.parse(try config.serialized()))
    #expect(again == config)
    #expect(config.object["pausedUntil"]?.stringValue?.hasPrefix("2026-11-02T10:00:00") == true)
  }

  @Test func pausedUntilKeepsFractionalSeconds() throws {
    let config = Config(pausedUntil: Date(timeIntervalSince1970: 1_793_613_600.25))
    let again = try #require(Config.parse(try config.serialized()))
    #expect(again.pausedUntil == config.pausedUntil)
  }

  @Test func wrongTypedOrUnparsablePausedUntilReadsAsAbsent() throws {
    #expect(try #require(parse(#"{"pausedUntil":5}"#)).pausedUntil == nil)
    #expect(try #require(parse(#"{"pausedUntil":"soon"}"#)).pausedUntil == nil)
  }
}
