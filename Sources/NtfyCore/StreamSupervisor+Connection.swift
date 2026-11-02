import Foundation

/// The body of one connection attempt: topics, catch-up, then the live stream.
extension StreamSupervisor {
  func runConnection(_ id: Int) async {
    do {
      let topics = try await resolveTopics()
      guard isCurrent(id) else { return }
      currentTopics = topics
      let since = try await prepareCursor(topics: topics)
      guard isCurrent(id) else { return }
      let events = ports.stream.events(topics: topics, since: since)
      for try await event in events {
        guard isCurrent(id) else { return }
        try await handle(event, topics: topics, id: id)
      }
      guard isCurrent(id) else { return }
      apply(.finished)
    } catch {
      guard isCurrent(id) else { return }
      apply(.failed((error as? NtfyError) ?? .serverUnreachable))
    }
  }

  private func handle(_ event: StreamEvent, topics: [String], id: Int) async throws(NtfyError) {
    switch event {
    case .open:
      apply(.opened)
      startRediscovery(id)
    case .keepalive:
      apply(.activity)
    case .pollRequest:
      apply(.activity)
      if let stored = try await ports.cursor.load() {
        _ = try await catchUp(topics: topics, since: stored)
      }
    case .message(let message):
      apply(.activity)
      try await ingest.ingest(message)
    case .messageDelete, .messageClear:
      apply(.activity)
      await options.sink?(event)
    }
  }

  /// Topics from the account and the selection. Dropped names are logged, never fatal.
  func resolveTopics() async throws(NtfyError) -> [String] {
    var discovered: [String] = []
    if selection.override == nil {
      discovered = try await ports.topics.subscribedTopics()
    }
    let resolved = TopicResolver.resolve(selection: selection, discovered: discovered)
    if !resolved.invalid.isEmpty {
      options.log("ignored \(resolved.invalid.count) invalid topic name(s)")
    }
    if !resolved.overflow.isEmpty {
      options.log(
        "ignored \(resolved.overflow.count) topic(s) beyond the \(TopicResolver.maxTopics) limit")
    }
    guard !resolved.topics.isEmpty else { throw .invalidResponse("no topics to subscribe to") }
    return resolved.topics
  }

  /// Returns the `since` for the stream. With a stored cursor, everything after it is fetched
  /// first so the missed-message policy applies; on a first run the cursor starts at "now", which
  /// drops nothing from history between here and the connection (`latest` would).
  private func prepareCursor(topics: [String]) async throws(NtfyError) -> String {
    if let stored = try await ports.cursor.load() {
      return try await catchUp(topics: topics, since: stored)
    }
    let start = String(Int(ports.clock.now().timeIntervalSince1970))
    do throws(NtfyError) {
      try await ports.cursor.save(start)
    } catch {
      options.log("first-run cursor not saved: \(error)")
    }
    return start
  }

  private func catchUp(topics: [String], since: String) async throws(NtfyError) -> String {
    let messages = try await ports.poller.poll(topics: topics, since: since)
    return try await ingest.ingestCatchUp(messages) ?? since
  }

  // MARK: Rediscovery

  func startRediscovery(_ id: Int) {
    rediscoveryTask?.cancel()
    guard selection.override == nil else { return }
    rediscoveryTask = Task { await self.rediscover(id) }
  }

  /// Reconnects when the account's topics changed since this connection was opened. A result that
  /// arrives after the connection was replaced is dropped; a terminal failure ends the connection
  /// like any other.
  private func rediscover(_ id: Int) async {
    while isCurrent(id) {
      do { try await ports.clock.sleep(for: options.rediscoveryInterval) } catch { return }
      guard isCurrent(id) else { return }
      do throws(NtfyError) {
        let topics = try await resolveTopics()
        guard isCurrent(id) else { return }
        if Set(topics) != Set(currentTopics) {
          apply(.reconnect)
          return
        }
      } catch {
        guard isCurrent(id) else { return }
        if ReconnectMachine.isTerminal(error) {
          apply(.failed(error))
          return
        }
        options.log("topic rediscovery failed: \(error)")
      }
    }
  }
}
