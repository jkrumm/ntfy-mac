import Foundation
import NtfyCore

/// What the sidebar picks and the filter bar above the list shows and does.
extension HistoryModel {
  /// The views the sidebar offers: everything, the messages that wait for an acknowledgement,
  /// or one topic.
  public enum Scope: Sendable, Hashable {
    case all
    case needsAcknowledgement
    case topic(String)
  }

  public var scope: Scope {
    if needsAcknowledgementOnly { return .needsAcknowledgement }
    return selectedTopic.map(Scope.topic) ?? .all
  }

  /// Moves to a view of the sidebar; the search and the filters stay.
  public func show(_ scope: Scope) {
    switch scope {
    case .all:
      needsAcknowledgementOnly = false
      selectedTopic = nil
    case .needsAcknowledgement:
      selectedTopic = nil
      needsAcknowledgementOnly = true
    case .topic(let topic):
      needsAcknowledgementOnly = false
      selectedTopic = topic
    }
  }

  /// The name of the view above the list.
  public var scopeTitle: String {
    switch scope {
    case .all: "All messages"
    case .needsAcknowledgement: "Unacknowledged"
    case .topic(let topic): topic
    }
  }

  /// Search, priority, date or unread narrows the list (the selected topic does not).
  public var isNarrowing: Bool {
    !trimmedSearch.isEmpty || minPriority != nil || dateFilter != .all || unreadOnly
  }

  /// Drops search and the filters but stays in the topic or the acknowledgement view.
  public func clearNarrowing() {
    let kept = scope
    resetFilters()
    show(kept)
  }

  /// The Acknowledge action belongs on this row: its priority needs one and it has none yet.
  public func canAcknowledge(_ row: MessageRow) -> Bool {
    acknowledgePolicy.isPending(priority: row.priority, isAcknowledged: row.isAcknowledged)
  }
}
