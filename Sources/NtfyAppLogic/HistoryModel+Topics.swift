import Foundation
import NtfyCore

/// The settings of a topic that the sidebar's context menu changes. They write to the same config
/// file the Settings window and the CLI edit, through `ConfigStore.update` and
/// `Config.updateTopic`, so every path agrees on what a value means.
extension HistoryModel {
  public func settings(for topic: String) -> TopicSettings {
    topicSettings[topic] ?? TopicSettings()
  }

  /// The topic's emoji, nil without one; what the sidebar and the list show before the name.
  public func emoji(for topic: String) -> String? { topicSettings[topic]?.emoji }

  public func setMute(_ mute: Bool, topic: String) async {
    await updateTopic(topic) { $0.mute = mute }
  }

  public func setHideFromAll(_ hide: Bool, topic: String) async {
    await updateTopic(topic) { $0.hideFromAll = hide }
  }

  /// 1...5, or nil for no filter.
  public func setMinPriority(_ priority: Int?, topic: String) async {
    let pinned = priority.map { Priority(clamping: $0).rawValue }
    await updateTopic(topic) { $0.minPriority = pinned }
  }

  /// Blank or nil removes the emoji.
  public func setEmoji(_ emoji: String?, topic: String) async {
    let normalized = TopicSettings.normalizedEmoji(emoji)
    await updateTopic(topic) { $0.emoji = normalized }
  }

  private func updateTopic(
    _ topic: String, _ change: @escaping @Sendable (inout TopicSettings) -> Void
  ) async {
    do throws(NtfyError) {
      try await config.update { $0.updateTopic(topic, change) }
    } catch {
      log("topic setting not stored: \(error)")
    }
    await refresh()
  }
}
