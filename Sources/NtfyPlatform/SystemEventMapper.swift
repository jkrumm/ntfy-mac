import AppKit
import NtfyCore

/// The pure part of `SystemEventMonitor`: which AppKit notification and which path state become
/// which `SystemEvent`.
public struct SystemEventMapper: Sendable {
  private var lastOnline = false
  private var hasReported = false

  public init() {}

  /// `NWPath.Status.satisfied` means connections can be established, on whatever interface; every
  /// other status is offline. The first update is always reported, later ones only when
  /// online-ness flips, so an interface change that stays satisfied is silent.
  public mutating func pathEvent(satisfied: Bool) -> SystemEvent? {
    defer {
      lastOnline = satisfied
      hasReported = true
    }
    guard !hasReported || lastOnline != satisfied else { return nil }
    return .pathChanged(online: satisfied)
  }

  /// The notifications `workspaceNotifications` lists, all posted by
  /// `NSWorkspace.shared.notificationCenter`.
  public static func workspaceEvent(named name: Notification.Name) -> SystemEvent? {
    switch name {
    case NSWorkspace.didWakeNotification: return .didWake
    case NSWorkspace.willSleepNotification: return .willSleep
    case NSWorkspace.screensDidSleepNotification: return .screensDidSleep
    case NSWorkspace.screensDidWakeNotification: return .screensDidWake
    default: return nil
    }
  }

  /// The lock and unlock notifications `SystemEventMonitor` takes from the distributed center.
  public static let lockNotification = Notification.Name("com.apple.screenIsLocked")
  public static let unlockNotification = Notification.Name("com.apple.screenIsUnlocked")

  public static func distributedEvent(named name: Notification.Name) -> SystemEvent? {
    switch name {
    case lockNotification: return .screenLocked
    case unlockNotification: return .screenUnlocked
    default: return nil
    }
  }

  public static let workspaceNotifications: [Notification.Name] = [
    NSWorkspace.didWakeNotification, NSWorkspace.willSleepNotification,
    NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
  ]
}
