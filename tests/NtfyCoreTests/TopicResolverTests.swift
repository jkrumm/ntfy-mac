import NtfyCore
import Testing

@Suite struct TopicResolverTests {
  @Test func discoveredAndExtraAreMergedWithoutDuplicates() {
    let resolved = TopicResolver.resolve(
      selection: TopicSelection(extra: ["b", "c", "a"]), discovered: ["a", "b", "a"])
    #expect(resolved.topics == ["a", "b", "c"])
    #expect(resolved.invalid.isEmpty)
    #expect(resolved.overflow.isEmpty)
  }

  @Test func overrideReplacesDiscoveryAndExtras() {
    let resolved = TopicResolver.resolve(
      selection: TopicSelection(override: ["only"], extra: ["x"]), discovered: ["a"])
    #expect(resolved.topics == ["only"])
  }

  @Test func emptyOverrideMeansNoTopicsRatherThanDiscovery() {
    let resolved = TopicResolver.resolve(
      selection: TopicSelection(override: []), discovered: ["a"])
    #expect(resolved.topics.isEmpty)
  }

  @Test func invalidNamesAreDroppedAndReported() {
    let tooLong = String(repeating: "a", count: 65)
    let resolved = TopicResolver.resolve(
      selection: TopicSelection(extra: ["has space", "ok_1-x", "", tooLong, "a/b"]),
      discovered: [])
    #expect(resolved.topics == ["ok_1-x"])
    #expect(resolved.invalid == ["has space", "", tooLong, "a/b"])
  }

  @Test func sixtyFourCharactersIsValid() {
    #expect(TopicResolver.isValid(String(repeating: "a", count: 64)))
  }

  @Test func capsAtTheServerLimitAndReportsWhatDidNotFit() {
    let names = (0..<152).map { "t\($0)" }
    let resolved = TopicResolver.resolve(selection: TopicSelection(), discovered: names)
    #expect(resolved.topics.count == TopicResolver.maxTopics)
    #expect(resolved.topics.first == "t0")
    #expect(resolved.overflow == ["t150", "t151"])
  }

  @Test func duplicatesDoNotCountAgainstTheLimit() {
    let names = (0..<150).map { "t\($0)" }
    let resolved = TopicResolver.resolve(selection: TopicSelection(extra: names), discovered: names)
    #expect(resolved.topics.count == 150)
    #expect(resolved.overflow.isEmpty)
  }
}
