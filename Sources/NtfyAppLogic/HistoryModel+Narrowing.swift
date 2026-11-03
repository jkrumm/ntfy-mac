import Foundation
import NtfyCore

/// What the filter bar above the list shows and does.
extension HistoryModel {
  /// Search, priority, date or unread narrows the list (the selected topic does not).
  public var isNarrowing: Bool {
    !trimmedSearch.isEmpty || minPriority != nil || dateFilter != .all || unreadOnly
  }

  /// Drops search and the filters but stays in the topic.
  public func clearNarrowing() {
    let topic = selectedTopic
    resetFilters()
    selectedTopic = topic
  }

  /// The Acknowledge action belongs on this row: its priority needs one and it has none yet.
  public func canAcknowledge(_ row: MessageRow) -> Bool {
    acknowledgePolicy.isPending(priority: row.priority, isAcknowledged: row.isAcknowledged)
  }
}
