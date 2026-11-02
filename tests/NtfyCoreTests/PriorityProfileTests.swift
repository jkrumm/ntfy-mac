import Testing

@testable import NtfyCore

@Suite struct PriorityProfileTests {
  @Test(arguments: [
    (5, "Ping", InterruptionLevel.timeSensitive, 1.0, Duration?.none),
    (4, "Ping", .timeSensitive, 0.75, nil),
    (3, "Pop", .active, 0.5, .seconds(8)),
    (2, "Tink", .active, 0.25, .seconds(5)),
    (1, "Tink", .active, 0.0, .seconds(4)),
  ])
  func defaultTable(
    priority: Int, sound: String, level: InterruptionLevel, relevance: Double, dismiss: Duration?
  ) {
    let profile = PriorityProfile(priority: priority)
    #expect(profile.sound == sound)
    #expect(profile.interruption == level)
    #expect(profile.relevance == relevance)
    #expect(profile.dismissAfter == dismiss)
  }

  @Test func soundOverrideKeepsTheRest() {
    let profile = PriorityProfile(priority: 5, config: Config(sounds: [5: .named("Tink")]))
    #expect(profile.sound == "Tink")
    #expect(profile.interruption == .timeSensitive)
    #expect(profile.relevance == 1.0)
  }

  @Test func silentOverrideRemovesTheSound() {
    let profile = PriorityProfile(priority: 3, config: Config(sounds: [3: .silent]))
    #expect(profile.sound == nil)
    #expect(profile.interruption == .active)
  }

  @Test func unoverriddenPrioritiesKeepDefaults() {
    #expect(
      PriorityProfile(priority: 4, config: Config(sounds: [5: .named("Glass")])).sound == "Ping")
  }

  @Test func dismissOverrideKeepsTheRest() {
    let profile = PriorityProfile(priority: 3, config: Config(dismiss: [3: 20]))
    #expect(profile.dismissAfter == .seconds(20))
    #expect(profile.sound == "Pop")
    #expect(profile.interruption == .active)
  }

  @Test func dismissZeroMeansNever() {
    #expect(PriorityProfile(priority: 3, config: Config(dismiss: [3: 0])).dismissAfter == nil)
  }

  @Test(arguments: [0, 6, 99, -1])
  func unknownPriorityFallsBackToThree(priority: Int) {
    #expect(PriorityProfile(priority: priority) == PriorityProfile(priority: 3))
  }
}
