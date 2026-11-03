import NtfyCore

/// Which messages need an acknowledgement. The same threshold the notification's Acknowledge
/// button and the re-alert use (`Config.reAlertMinPriority`), so the menu and the History window
/// offer "Acknowledge" exactly where the notification does. A lower priority is read, never
/// acknowledged: opening it is enough. Acknowledgement already stored on any message stays as it is.
public struct AcknowledgePolicy: Sendable, Hashable {
  /// Messages at this priority or above need an acknowledgement.
  public let minPriority: Priority

  public init(config: Config) {
    minPriority = Priority(clamping: config.reAlertMinPriority)
  }

  public init(minPriority: Priority = Priority(clamping: Config.Defaults.reAlertMinPriority)) {
    self.minPriority = minPriority
  }

  public func requires(_ priority: Priority) -> Bool { priority >= minPriority }

  /// The Acknowledge button belongs on this message: it needs one and has none yet.
  public func isPending(priority: Priority, isAcknowledged: Bool) -> Bool {
    requires(priority) && !isAcknowledged
  }
}
