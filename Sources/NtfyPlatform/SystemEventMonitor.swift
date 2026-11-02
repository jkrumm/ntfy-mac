import AppKit
import Network
import NtfyCore
import Synchronization

/// Wake, sleep and network-path changes of this Mac, as `SystemEvent`s.
///
/// Every `events()` call starts its own observers and tears them down when the stream ends. The
/// first event is always the current network state; later `pathChanged` events are only sent
/// when online-ness flips (`SystemEventMapper`).
public struct SystemEventMonitor: SystemEvents {
  public init() {}

  public func events() -> AsyncStream<SystemEvent> {
    AsyncStream(SystemEvent.self, bufferingPolicy: .unbounded) { continuation in
      let center = NSWorkspace.shared.notificationCenter
      let observers = [NSWorkspace.didWakeNotification, NSWorkspace.willSleepNotification]
        .map { Self.observe($0, on: center, into: continuation) }
      let monitor = NWPathMonitor()
      let reported = Mutex(SystemEventMapper())
      monitor.pathUpdateHandler = { path in
        let event = reported.withLock { $0.pathEvent(satisfied: path.status == .satisfied) }
        if let event { continuation.yield(event) }
      }
      monitor.start(queue: DispatchQueue(label: "\(Log.subsystem).path"))
      continuation.onTermination = { _ in
        monitor.cancel()
        for observer in observers { observer.cancel() }
      }
    }
  }

  private static func observe(
    _ name: Notification.Name, on center: NotificationCenter,
    into continuation: AsyncStream<SystemEvent>.Continuation
  ) -> Task<Void, Never> {
    Task {
      for await _ in center.notifications(named: name) {
        if let event = SystemEventMapper.workspaceEvent(named: name) {
          continuation.yield(event)
        }
      }
    }
  }
}
