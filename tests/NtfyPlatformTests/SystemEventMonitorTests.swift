import NtfyCore
import NtfyPlatform
import Testing

@Suite struct SystemEventMonitorTests {
  @Test func theFirstEventIsTheCurrentNetworkState() async {
    var iterator = SystemEventMonitor().events().makeAsyncIterator()
    let first = await iterator.next()
    guard case .pathChanged? = first else {
      Issue.record("expected the initial pathChanged, got \(String(describing: first))")
      return
    }
  }

  @Test func cancellingTheConsumerEndsTheStream() async {
    let events = SystemEventMonitor().events()
    let consumer = Task {
      for await _ in events {}
    }
    consumer.cancel()
    await consumer.value
  }

  @Test func manyStreamsCanBeCreatedAndDroppedWithoutHanging() async {
    for _ in 0..<20 {
      var iterator = SystemEventMonitor().events().makeAsyncIterator()
      _ = await iterator.next()
    }
  }
}
