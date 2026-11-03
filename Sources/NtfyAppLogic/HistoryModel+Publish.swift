import Foundation
import NtfyCore

/// The composer behind "New message…": publishes to a topic through the same `NtfyPublishing`
/// port `ntfy-mac publish` uses. The server echoes the message back over the stream, so it lands
/// in the list like any other.
extension HistoryModel {
  /// Every topic a message can go to: the ones with history, newest first, then subscribed ones
  /// that have none yet.
  public var composerTopics: [String] {
    let known = topics.map(\.topic)
    return known + configuredTopics.filter { !known.contains($0) }.sorted()
  }

  public var composerAvailability: ComposerAvailability {
    let topic = composerTopic.flatMap { composerTopics.contains($0) ? $0 : nil }
    return (topic ?? selectedTopic ?? composerTopics.first).map { .ready(topic: $0) } ?? .noTopic
  }

  /// The popover opens: the selected topic is the target, else the one used last, else the
  /// newest. The priority starts at the default; the draft stays so a closed popover loses nothing.
  public func openComposer() {
    if let selectedTopic {
      composerTopic = selectedTopic
    } else if case .ready(let topic) = composerAvailability {
      composerTopic = topic
    }
    composerPriority = .default
    composerState = .idle
  }

  public var canSend: Bool {
    guard case .ready = composerAvailability, composerState != .sending else { return false }
    return !Self.trimmed(draft).isEmpty
  }

  /// Publishes the draft. On success the draft is cleared unless it was edited meanwhile; on
  /// failure it stays and `composerState` says why.
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
        _ = try await publishing.publish(
          PublishRequest(
            topic: topic, message: text, priority: priority == .default ? nil : priority))
      }
    } catch {
      composerState = .failed(ComposerErrorText.describe(error))
      return
    }
    if Self.trimmed(draft) == text { draft = "" }
    composerState = .idle
    await refresh()
  }

  func clearComposerFailure() {
    if case .failed = composerState { composerState = .idle }
  }

  private static func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
