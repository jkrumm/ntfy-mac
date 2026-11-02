import Foundation
import NtfyCore

/// The composer: publishes to the selected conversation through the same `NtfyPublishing` port
/// `ntfy-mac publish` uses. The server echoes the message back over the stream, so it lands in
/// the thread like any other; this app only remembers its id to draw the bubble on the right.
extension HistoryModel {
  public var composerAvailability: ComposerAvailability {
    selectedTopic.map { .ready(topic: $0) } ?? .needsConversation
  }

  /// The text typed for the selected conversation; each conversation keeps its own draft.
  public var draft: String {
    get { selectedTopic.flatMap { drafts[$0] } ?? "" }
    set {
      guard let topic = selectedTopic else { return }
      drafts[topic] = newValue.isEmpty ? nil : newValue
      if case .failed = composerState { composerState = .idle }
    }
  }

  public var canSend: Bool {
    guard case .ready = composerAvailability, composerState != .sending else { return false }
    return !Self.trimmed(draft).isEmpty
  }

  /// Publishes the draft to the selected topic. On success the draft is cleared; on failure it
  /// stays and `composerState` says why.
  public func send() async {
    guard canSend, case .ready(let topic) = composerAvailability else { return }
    let text = Self.trimmed(draft)
    let priority = composerPriority
    composerState = .sending
    do throws(NtfyError) {
      guard let provider = publisher else {
        composerState = .failed(ComposerErrorText.notConfigured)
        return
      }
      switch try await provider.resolve() {
      case .notConfigured:
        composerState = .failed(ComposerErrorText.notConfigured)
        return
      case .invalid(let reason):
        composerState = .failed(reason)
        return
      case .ready(let publishing):
        let sent = try await publishing.publish(
          PublishRequest(
            topic: topic, message: text, priority: priority == .default ? nil : priority))
        ownKeys.insert(MessageKey(topic: sent.topic, id: sent.id))
      }
    } catch {
      composerState = .failed(ComposerErrorText.describe(error))
      return
    }
    drafts[topic] = nil
    composerState = .idle
    await refresh()
  }

  private static func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
