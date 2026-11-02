import Foundation
import NtfyCore

/// What the window can do to messages. Each action refreshes afterwards, so the model is right
/// without waiting for the history signal. A `key` of nil means the selected message; an action
/// on nothing does nothing.
extension HistoryModel {
  /// Acknowledges the message (which also reads it) and withdraws its notification.
  public func acknowledge(_ key: MessageKey? = nil) async {
    guard let key = key ?? selection else { return }
    await handles?.delivery.acknowledge(topic: key.topic, id: key.id)
    await refresh()
  }

  public func markRead(_ key: MessageKey? = nil) async {
    guard let key = key ?? selection else { return }
    await perform("mark read") { inbox throws(NtfyError) in
      try await inbox.markRead(topic: key.topic, id: key.id)
    }
  }

  public func markUnread(_ key: MessageKey? = nil) async {
    guard let key = key ?? selection else { return }
    await perform("mark unread") { inbox throws(NtfyError) in
      try await inbox.markUnread(topic: key.topic, id: key.id)
    }
  }

  /// Reads every message of the topic; nil reads every topic.
  public func markAllRead(topic: String?) async {
    let names = topic.map { [$0] } ?? topics.map(\.topic)
    await perform("mark all read") { inbox throws(NtfyError) in
      for name in names { try await inbox.markAllRead(topic: name) }
    }
  }

  /// Shows the message again as a notification at the choice's time.
  public func remind(_ choice: RemindChoice, _ key: MessageKey? = nil) async {
    guard let key = key ?? selection else { return }
    let time = choice.time(from: clock.now(), calendar: calendar)
    do throws(NtfyError) {
      let known = try await handles?.messages.remind(topic: key.topic, id: key.id, until: time)
      if known == false { log("remind: no message \(key.topic)/\(key.id)") }
    } catch {
      log("remind failed: \(error)")
    }
    await refresh()
  }

  /// Deletes the message (its whole sequence) and withdraws its notification.
  public func delete(_ key: MessageKey? = nil) async {
    guard let key = key ?? selection else { return }
    if key == selection { clearSelection() }
    _ = await handles?.messages.delete(topic: key.topic, id: key.id)
    await refresh()
  }

  /// Deletes every message of the topic. A selection inside it is cleared, and a filter on it is
  /// dropped, since the topic is gone.
  public func deleteAll(topic: String) async {
    if selection?.topic == topic { clearSelection() }
    _ = await handles?.messages.deleteAll(topic: topic)
    if selectedTopic == topic { selectedTopic = nil }
    await refresh()
  }

  /// Opens the selected message's click URL, which `MessageDetail` already limited to http,
  /// https and mailto. False when there is none or nothing could open it.
  public func openClickURL() async -> Bool {
    guard let url = detail?.clickURL else { return false }
    return await opener.open(url)
  }

  /// Everything the filters match, not just the loaded page, as a file for the save panel.
  /// nil when there is nothing to export or no history to read.
  public func export(_ format: ExportFormat) async -> HistoryExport? {
    guard let inbox = handles?.inbox else { return nil }
    var messages: [StoredMessage] = []
    do throws(NtfyError) {
      while true {
        let page = try await inbox.entries(
          currentQuery(limit: Self.exportPageSize, offset: messages.count))
        messages += page
        if page.count < Self.exportPageSize { break }
      }
    } catch {
      log("export failed: \(error)")
      return nil
    }
    guard !messages.isEmpty else { return nil }
    return HistoryExporter.export(messages, as: format, scope: selectedTopic, now: clock.now())
  }

  // MARK: Helpers

  static var exportPageSize: Int { 500 }

  private func perform(
    _ what: String, _ work: (any HistoryInbox) async throws(NtfyError) -> Void
  ) async {
    guard let inbox = handles?.inbox else { return }
    do throws(NtfyError) {
      try await work(inbox)
    } catch {
      log("\(what) failed: \(error)")
    }
    await refresh()
  }
}

/// The attachment preview: fetched on demand, one at a time, for the selected message.
extension HistoryModel {
  /// Starts downloading the selected message's attachment; `attachment` follows. Does nothing
  /// without one, or while a download runs. An expired attachment fails without a request.
  public func loadAttachment() {
    guard let file = detail?.attachment, let fetcher = handles?.attachments else { return }
    if case .loading = attachment { return }
    if file.isExpired {
      attachment = .failed("The server no longer has this attachment.")
      return
    }
    let key = selection
    attachment = .loading
    attachmentTask = Task {
      let outcome: AttachmentState
      do throws(NtfyError) {
        outcome = .ready(try await fetcher.fetch(file.source))
      } catch {
        outcome = .failed(Self.describe(error))
      }
      guard !Task.isCancelled, selection == key else { return }
      attachment = outcome
      attachmentTask = nil
    }
  }

  /// Stops a running download and returns to idle; a finished one stays as it is.
  public func cancelAttachment() {
    attachmentTask?.cancel()
    attachmentTask = nil
    attachment = .idle
  }

  private static func describe(_ error: NtfyError) -> String {
    switch error {
    case .unauthorized: "The server rejected the token."
    case .serverUnreachable: "The server could not be reached."
    case .redirected: "The server redirected the request."
    case .invalidResponse(let detail): detail.prefix(1).uppercased() + detail.dropFirst() + "."
    default: "The attachment could not be loaded."
    }
  }
}
