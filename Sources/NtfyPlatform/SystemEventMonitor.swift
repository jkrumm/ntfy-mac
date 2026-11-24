import AppKit
import Network
import NtfyCore
import Synchronization

/// Wake, sleep, display and network-path changes of this Mac, as `SystemEvent`s.
///
/// Every `events()` call starts its own observers and tears them down when the stream ends. The
/// first event is always the current network state; later `pathChanged` events are only sent
/// when online-ness flips (`SystemEventMapper`).
///
/// The workspace observers run their block on the posting thread and yield from it, so the events
/// reach the stream in the order the system posted them, and `willSleep` is queued before the
/// Mac goes to sleep. A task per notification would not keep that order.
public struct SystemEventMonitor: SystemEvents {
  public init() {}

  public func events() -> AsyncStream<SystemEvent> {
    AsyncStream(SystemEvent.self, bufferingPolicy: .unbounded) { continuation in
      let center = NSWorkspace.shared.notificationCenter
      let observers = SystemEventMapper.workspaceNotifications.map { name in
        center.addObserver(forName: name, object: nil, queue: nil) { _ in
          if let event = SystemEventMapper.workspaceEvent(named: name) {
            continuation.yield(event)
          }
        }
      }
      let distributed = DistributedNotificationCenter.default()
      let lockObservers = [
        SystemEventMapper.lockNotification, SystemEventMapper.unlockNotification,
      ]
      .map { name in
        distributed.addObserver(forName: name, object: nil, queue: nil) { _ in
          if let event = SystemEventMapper.distributedEvent(named: name) {
            continuation.yield(event)
          }
        }
      }
      let tokens = Observers(observers)
      let lockTokens = Observers(lockObservers)
      let monitor = NWPathMonitor()
      let reported = Mutex(SystemEventMapper())
      monitor.pathUpdateHandler = { path in
        let event = reported.withLock { $0.pathEvent(satisfied: path.status == .satisfied) }
        if let event { continuation.yield(event) }
      }
      monitor.start(queue: DispatchQueue(label: "\(Log.subsystem).path"))
      continuation.onTermination = { _ in
        monitor.cancel()
        tokens.remove(from: center)
        lockTokens.remove(from: distributed)
      }
    }
  }
}

/// The observer tokens, kept to remove them; `NSObjectProtocol` is not `Sendable`.
private final class Observers: @unchecked Sendable {
  private let tokens: [any NSObjectProtocol]

  init(_ tokens: [any NSObjectProtocol]) { self.tokens = tokens }

  func remove(from center: NotificationCenter) {
    for token in tokens { center.removeObserver(token) }
  }
}
