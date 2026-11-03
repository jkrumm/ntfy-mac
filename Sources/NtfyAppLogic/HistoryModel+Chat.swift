import Foundation
import NtfyCore

/// The chat side of the window: sidebar entries and marking messages read as they scroll by.
extension HistoryModel {
  // MARK: Conversations

  /// One entry per topic from its newest messages. A few messages are read, not one, so a topic
  /// whose last message carries no emoji tag can still borrow one from the one before.
  func buildConversations(
    _ summaries: [TopicSummary], in inbox: any HistoryInbox
  ) async throws(NtfyError) -> [Conversation] {
    let urgent = Set(
      try await inbox.unacknowledged(minPriority: acknowledgePolicy.minPriority).map(
        \.message.topic))
    var result: [Conversation] = []
    for summary in summaries {
      let newest = try await inbox.entries(
        HistoryQuery(topic: summary.topic, limit: Self.previewDepth))
      guard let latest = newest.first?.message else { continue }
      let isOwn = ownKeys.contains(MessageKey(topic: latest.topic, id: latest.id))
      result.append(
        Conversation(
          topic: summary.topic,
          avatar: ConversationAvatar(topic: summary.topic, tags: newest.map(\.message.tags)),
          preview: Conversation.preview(of: latest, isOwn: isOwn),
          time: summary.newest, unread: summary.unread, hasUrgent: urgent.contains(summary.topic)))
    }
    return Conversation.ordered(result)
  }

  static var previewDepth: Int { 5 }

  /// The conversation of the topic, nil for an unknown one.
  public func conversation(_ topic: String) -> Conversation? {
    conversations.first { $0.topic == topic }
  }

  /// Search, priority, date or unread narrows the thread (the conversation itself does not).
  public var isNarrowing: Bool {
    !trimmedSearch.isEmpty || minPriority != nil || dateFilter != .all || unreadOnly
  }

  /// Drops search and the filters but stays in the conversation.
  public func clearNarrowing() {
    let topic = selectedTopic
    resetFilters()
    selectedTopic = topic
  }

  // MARK: Reading as it scrolls by

  /// The view shows the bubble. Once the thread has stayed put for `readDebounce`, every unread
  /// message still on screen is marked read in one go; scrolling restarts the wait.
  public func messageAppeared(_ key: MessageKey) {
    visibleKeys.insert(key)
    readTask?.cancel()
    readTask = Task {
      do { try await clock.sleep(for: readDebounce) } catch { return }
      await markVisibleRead()
    }
  }

  public func messageDisappeared(_ key: MessageKey) {
    visibleKeys.remove(key)
  }

  /// Marks the unread messages that are on screen read and refreshes once.
  func markVisibleRead() async {
    let unread = thread.filter { !$0.detail.isRead && visibleKeys.contains($0.key) }.map(\.key)
    guard !unread.isEmpty, let inbox = handles?.inbox else { return }
    do throws(NtfyError) {
      for key in unread { try await inbox.markRead(topic: key.topic, id: key.id) }
    } catch {
      log("mark read failed: \(error)")
    }
    await refresh()
  }
}
