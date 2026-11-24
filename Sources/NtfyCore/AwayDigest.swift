import Foundation

/// The digest of the messages missed since a moment: how many, and what to tell the user.
public struct AwayDigest: Sendable, Hashable {
  public let count: Int
  public let text: String
  /// The text came from the model; false for the deterministic fallback.
  public let usedModel: Bool
  /// Why the model's text is missing although a summarizer was asked.
  public let failure: String?

  public var title: String {
    "While you were away · \(count) \(count == 1 ? "message" : "messages")"
  }

  public init(count: Int, text: String, usedModel: Bool, failure: String? = nil) {
    self.count = count
    self.text = text
    self.usedModel = usedModel
    self.failure = failure
  }
}

/// Collects the messages that were delivered as notifications in a window and summarizes them.
public struct DigestBuilder: Sendable {
  /// Most messages read from the history for one digest.
  public static let readLimit = 1000

  private let inbox: any HistoryInbox
  private let log: @Sendable (String) -> Void

  public init(inbox: any HistoryInbox, log: @escaping @Sendable (String) -> Void = { _ in }) {
    self.inbox = inbox
    self.log = log
  }

  /// The messages from `since` on that were shown as notifications: notified, and not kept back by
  /// their topic's settings (mute, minimum priority). Newest first.
  public func collect(since: Date, config: Config) async throws(NtfyError) -> [StoredMessage] {
    let rows = try await inbox.entries(HistoryQuery(since: since, limit: Self.readLimit))
    return rows.filter { $0.notifiedAt != nil && !config.suppresses($0.message) }
  }

  /// The digest of `messages`. With a summarizer the model writes the text; without one, or when
  /// it fails, the deterministic text stands in and the failure is logged, never thrown.
  public func digest(
    of messages: [StoredMessage], config: Config, summarizer: (any MessageSummarizing)?
  ) async -> AwayDigest {
    let fallback = Self.deterministicText(for: messages, config: config)
    guard let summarizer else {
      return AwayDigest(count: messages.count, text: fallback, usedModel: false)
    }
    let entries = messages.prefix(SummaryPrompt.entryLimit).map { stored in
      DigestEntry(
        topic: stored.message.topic, priority: stored.message.priority.rawValue,
        time: stored.message.time, title: stored.message.title, body: stored.message.body,
        acknowledged: stored.isAcknowledged)
    }
    do throws(NtfyError) {
      let text = try await summarizer.summarize(Array(entries))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw NtfyError.invalidResponse("empty summary") }
      return AwayDigest(count: messages.count, text: text, usedModel: true)
    } catch {
      log("summary not written by the model: \(error)")
      return AwayDigest(
        count: messages.count, text: fallback, usedModel: false, failure: String(describing: error))
    }
  }

  /// `7 messages: ci 4, alerts 3, 2 unacknowledged`. The topics are listed by count, then name;
  /// unacknowledged counts the messages that still wait for an acknowledgement.
  public static func deterministicText(for messages: [StoredMessage], config: Config) -> String {
    var perTopic: [String: Int] = [:]
    for stored in messages { perTopic[stored.message.topic, default: 0] += 1 }
    let ordered = perTopic.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    var parts = ordered.prefix(maxTopics).map { "\($0.key) \($0.value)" }
    if ordered.count > maxTopics { parts.append("\(ordered.count - maxTopics) more topics") }
    let waiting = messages.filter {
      !$0.isAcknowledged && $0.message.priority.rawValue >= config.reAlertMinPriority
    }.count
    if waiting > 0 { parts.append("\(waiting) unacknowledged") }
    let noun = messages.count == 1 ? "message" : "messages"
    return "\(messages.count) \(noun): " + parts.joined(separator: ", ")
  }

  private static let maxTopics = 6
}
