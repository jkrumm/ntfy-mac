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
}
