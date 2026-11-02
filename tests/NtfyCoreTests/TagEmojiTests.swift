import Testing

@testable import NtfyCore

@Suite struct TagEmojiTests {
  @Test func knownTagsBecomeEmoji() {
    #expect(TagEmoji.render(["warning"]) == "⚠️")
    #expect(TagEmoji.render(["rotating_light"]) == "🚨")
    #expect(TagEmoji.render(["+1"]) == "👍")
    #expect(TagEmoji.render(["white_check_mark"]) == "✅")
  }

  @Test func unknownTagsStayText() {
    #expect(TagEmoji.render(["my-custom-tag"]) == "my-custom-tag")
  }

  @Test func mixedAndMultipleTagsJoinWithASpace() {
    #expect(TagEmoji.render(["fire", "custom"]) == "🔥 custom")
    #expect(TagEmoji.render(["warning", "+1"]) == "⚠️ 👍")
  }

  @Test func emptyIsEmpty() {
    #expect(TagEmoji.render([]).isEmpty)
  }

  @Test func tableMatchesTheGemojiAliasCountOf1x() {
    #expect(TagEmoji.count == 1913)
  }
}
