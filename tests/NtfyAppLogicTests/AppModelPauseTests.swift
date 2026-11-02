import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct AppModelPauseTests {
  @Test func pauseStoresTheEndInTheConfigAndResumeClearsIt() async {
    let rig = ModelRig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.connection == .notConfigured })

    await rig.model.pause(.duration(30 * 60))
    let end = rig.pipeline.clock.now().addingTimeInterval(30 * 60)
    #expect(rig.model.pausedUntil == end)
    #expect(await rig.pipeline.config.load().pausedUntil == end)
    #expect(!rig.model.isPausedIndefinitely)

    await rig.model.resume()
    #expect(rig.model.pausedUntil == nil)
    #expect(await rig.pipeline.config.load().pausedUntil == nil)
    rig.model.stop()
  }

  @Test func pausingIndefinitelyUsesTheFarFutureDate() async {
    let rig = ModelRig()
    rig.model.start()
    await rig.model.pause(.indefinitely)
    #expect(rig.model.pausedUntil == PauseWindow.indefinite)
    #expect(rig.model.isPausedIndefinitely)
    rig.model.stop()
  }

  @Test func aPauseWrittenByTheCLIIsPickedUpFromTheConfigSignal() async {
    let rig = ModelRig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.connection == .notConfigured })
    let end = rig.pipeline.clock.now().addingTimeInterval(3600)
    await rig.pipeline.config.update { $0.pausedUntil = end }
    rig.configChanges.fire()
    #expect(await rig.eventually { rig.model.pausedUntil == end })
    rig.model.stop()
  }

  @Test func aPauseThatEndedReadsAsNotPaused() async {
    let past = FakeClock().now().addingTimeInterval(-60)
    let rig = ModelRig(pipeline: PipelineFixture(config: Config(pausedUntil: past)))
    rig.model.start()
    #expect(await rig.eventually { rig.model.connection == .notConfigured })
    #expect(rig.model.pausedUntil == nil)
    rig.model.stop()
  }

  @Test func aTimedPauseEndsByItself() async {
    let rig = ModelRig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.connection == .notConfigured })
    await rig.model.pause(.duration(600))
    #expect(rig.model.pausedUntil != nil)
    #expect(await rig.eventually { rig.pipeline.clock.sleeperCount > 0 })
    rig.pipeline.clock.advance(by: .seconds(601))
    #expect(await rig.eventually { rig.model.pausedUntil == nil })
    rig.model.stop()
  }

  @Test func untilMorningIsTheNextEightOClock() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    func date(_ hour: Int, day: Int = 10) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))
        ?? .distantPast
    }
    #expect(PauseChoice.untilMorning.end(from: date(22), calendar: calendar) == date(8, day: 11))
    #expect(PauseChoice.untilMorning.end(from: date(8), calendar: calendar) == date(8, day: 11))
    #expect(PauseChoice.untilMorning.end(from: date(3), calendar: calendar) == date(8))
  }
}
