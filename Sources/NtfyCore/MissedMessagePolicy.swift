import Foundation

/// What to do with messages that arrived while the app was away.
public enum MissedMessageDecision: Sendable, Hashable {
  /// Store only.
  case silent
  /// One notification standing in for all of them.
  case summary(count: Int, oldestTopic: String)
  /// Notify each one.
  case individual([NtfyMessage])
}

/// Decides how loudly a batch of missed messages is announced, by the age of the oldest one.
public enum MissedMessagePolicy {
  /// Older than this: one summary instead of individual notifications.
  public static let individualLimit: TimeInterval = 60 * 60
  /// Older than this: no notification at all.
  public static let silentLimit: TimeInterval = 12 * 60 * 60

  public static func decide(_ messages: [NtfyMessage], now: Date) -> MissedMessageDecision {
    guard let oldest = messages.min(by: { $0.time < $1.time }) else { return .silent }
    let age = now.timeIntervalSince(oldest.time)
    if age > silentLimit { return .silent }
    if age > individualLimit { return .summary(count: messages.count, oldestTopic: oldest.topic) }
    return .individual(messages)
  }
}
