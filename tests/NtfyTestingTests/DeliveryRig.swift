import Foundation
import NtfyCore
import NtfyTesting

/// A delivery service wired to fakes, with helpers that wait deterministically: no real
/// sleeping, only bounded yield loops and a hand-driven clock.
struct DeliveryRig {
  let clock = FakeClock()
  let poster: RecordingNotificationPoster
  let history: InMemoryHistoryStore
  let config: InMemoryConfigStore
  let service: DeliveryService

  init(
    config initial: Config = .withoutTimers,
    poster: RecordingNotificationPoster = RecordingNotificationPoster(),
    meeting: (any MeetingStateProviding)? = nil
  ) {
    self.poster = poster
    history = InMemoryHistoryStore(clock: clock)
    config = InMemoryConfigStore(initial)
    service = DeliveryService(
      poster: poster, history: history, inbox: history, config: config, clock: clock,
      calendar: Self.utc, meeting: meeting)
  }

  /// The fake clock starts at 22:13 UTC on 2023-11-14.
  static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
  }()

  /// Seconds from now until the next 07:00 UTC.
  var untilMorning: TimeInterval {
    QuietHours().nextEnd(after: clock.now(), calendar: Self.utc).timeIntervalSince(clock.now())
  }

  func message(
    _ id: String, topic: String = "t", priority: Int = 3, sequence: String? = nil,
    age: TimeInterval = 0
  ) -> NtfyMessage {
    NtfyMessage(
      id: id, topic: topic, time: clock.now().addingTimeInterval(-age), body: "body \(id)",
      priority: Priority(clamping: priority), sequenceID: sequence)
  }

  /// Stores the message the way ingest does, then hands it to the service.
  @discardableResult
  func receive(
    _ id: String, topic: String = "t", priority: Int = 3, sequence: String? = nil
  ) async throws -> NtfyMessage {
    let message = message(id, topic: topic, priority: priority, sequence: sequence)
    try await history.append(message)
    await service.deliver(message)
    return message
  }

  // MARK: Waiting

  func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<200_000 {
      if await condition() { return true }
      await Task.yield()
    }
    return false
  }

  /// Lets every runnable task run; for asserting that nothing more happens.
  func settle() async {
    for _ in 0..<3000 { await Task.yield() }
  }

  func waitForPosts(_ count: Int) async -> Bool {
    await eventually { await poster.posted.count >= count }
  }

  func waitForAttempts(_ count: Int) async -> Bool {
    await eventually { await poster.attempts >= count }
  }

  func waitForSleepers(_ count: Int) async -> Bool {
    await eventually { clock.sleeperCount == count }
  }

  // MARK: Driving

  func advance(_ seconds: Double) async {
    clock.advance(by: .seconds(seconds))
    await settle()
  }

  /// Waits for the drain loop to be sleeping on the pacing, then lets one interval pass.
  func nextSlot() async {
    _ = await waitForSleepers(1)
    await advance(1.5)
  }

  /// Delivers a message and waits for its post, so the next one meets the pacing.
  func occupyTheSlot() async throws {
    try await receive("blocker", topic: "slot", priority: 4)
    _ = await waitForPosts(1)
  }
}

extension Config {
  /// No auto-dismiss and no re-alert, so a post leaves no timer on the clock.
  static var withoutTimers: Config {
    Config(dismiss: [1: 0, 2: 0, 3: 0, 4: 0, 5: 0], reAlert: false)
  }
}
