import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct DeliverySinkTests {
  @Test func theSinkForwardsOnlyDeleteAndClear() async {
    let recorder = RecordingDelivery()
    let sink = recorder.eventSink()
    await sink(.open)
    await sink(.keepalive)
    await sink(.pollRequest)
    await sink(.message(NtfyMessage(id: "m", topic: "t", time: Date(), body: "b")))
    await sink(.messageDelete(topic: "t", sequenceID: "s1"))
    await sink(.messageClear(topic: "t", sequenceID: "s2"))
    #expect(await recorder.withdrawn == [.init(topic: "t", sequenceID: "s1")])
    #expect(await recorder.cleared == [.init(topic: "t", sequenceID: "s2")])
    #expect(await recorder.delivered.isEmpty)
  }
}

/// The supervisor, a real delivery service and the fakes, end to end.
@Suite struct SupervisorDeliveryWiringTests {
  private struct Wiring {
    let rig: SupervisorRig
    let poster = RecordingNotificationPoster()
    let clock = FakeClock()
    let service: DeliveryService

    init() {
      let history = InMemoryHistoryStore(clock: clock)
      service = DeliveryService(
        poster: poster, history: history, inbox: history,
        config: InMemoryConfigStore(Config(dismiss: [3: 0])), clock: clock)
      let service = service
      rig = SupervisorRig(
        cursor: "c0", delivery: service, history: history,
        configure: { $0.sink = service.eventSink() })
    }
  }

  @Test func aMessageDeleteForAQueuedMessageDropsItBeforeItIsShown() async {
    let wiring = Wiring()
    let rig = wiring.rig
    #expect(await rig.connect())
    rig.stream.send(rig.message("m1"))
    #expect(await wiring.poster.waitForPost(count: 1))
    rig.stream.send(rig.message("m2"))
    #expect(await rig.eventually { await rig.cursor.load() == "m2" })
    rig.stream.send(.messageDelete(topic: "alpha", sequenceID: "m2"))
    #expect(await rig.eventually { await rig.history.recent(limit: 10).map(\.id) == ["m1"] })
    wiring.clock.advance(by: .seconds(1.5))
    await rig.settle()
    #expect(await wiring.poster.postedIDs == ["m1"])
    await rig.supervisor.stop()
    await wiring.service.shutdown()
  }

  @Test func aMessageClearForAShownMessageRemovesItsNotification() async {
    let wiring = Wiring()
    let rig = wiring.rig
    #expect(await rig.connect())
    rig.stream.send(rig.message("m1"))
    #expect(await wiring.poster.waitForPost(count: 1))
    rig.stream.send(.messageClear(topic: "alpha", sequenceID: "m1"))
    #expect(await rig.eventually { await wiring.poster.removed == ["alpha/m1"] })
    let stored = await rig.history.entries(HistoryQuery()).first
    #expect(stored?.isAcknowledged == true)
    await rig.supervisor.stop()
    await wiring.service.shutdown()
  }
}

extension RecordingNotificationPoster {
  fileprivate func waitForPost(count: Int) async -> Bool {
    for _ in 0..<200_000 {
      if posted.count >= count { return true }
      await Task.yield()
    }
    return false
  }
}
