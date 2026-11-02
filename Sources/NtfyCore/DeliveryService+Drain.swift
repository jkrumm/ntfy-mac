import Foundation

extension DeliveryService {
  enum Outcome { case posted, failed, skipped }

  func startDraining() {
    guard drainTask == nil, !stopped, !queue.isEmpty else { return }
    drainTask = Task { await self.drain() }
  }

  /// Posts one item at a time, `minimumInterval` apart, until the queue is empty. Sleeps only
  /// while it waits for the pacing; an idle service has no task here.
  private func drain() async {
    while !Task.isCancelled, !queue.isEmpty {
      let wait = queue.delay(at: clock.now())
      if wait > 0 {
        do { try await clock.sleep(for: .seconds(wait)) } catch { break }
        continue
      }
      guard var item = queue.next() else { break }
      item.attempts += 1
      let outcome = await post(item)
      if outcome != .skipped { queue.recordAttempt(at: clock.now()) }
      await retryOrDrop(item, after: outcome)
      dropAbandonedReminders()
    }
    drainTask = nil
  }

  private func retryOrDrop(_ item: DeliveryQueue.Item, after outcome: Outcome) async {
    guard outcome == .failed, !stopped, !Task.isCancelled else { return }
    guard item.attempts < item.maxAttempts else {
      log("notification given up after \(item.attempts) attempts; it stays unnotified")
      await keepReAlertChainAlive(item)
      return
    }
    queue.requeue(item)
  }

  /// A re-alert that could not be shown does not end the chain: the next tick tries again.
  private func keepReAlertChainAlive(_ item: DeliveryQueue.Item) async {
    guard case .message(let message, let repeatsLeft?) = item.payload else { return }
    let config = await currentConfig()
    guard !stopped else { return }
    scheduleRealert(
      message, repeatsLeft: repeatsLeft, interval: TimeInterval(config.reAlertIntervalSeconds))
  }

  private func post(_ item: DeliveryQueue.Item) async -> Outcome {
    switch item.payload {
    case .message(let message, let repeatsLeft):
      return await postMessage(message, repeatsLeft: repeatsLeft)
    case .summary(let count, let oldestTopic, let covers, let cause):
      return await postSummary(count: count, oldestTopic: oldestTopic, covers: covers, cause: cause)
    }
  }

  private func postMessage(_ message: NtfyMessage, repeatsLeft: Int?) async -> Outcome {
    let ref = MessageRef(topic: message.topic, id: message.id)
    inFlight = InFlight(ref: ref, identifier: message.notificationIdentifier)
    let loaded = await currentConfig()
    guard inFlight?.fate == .keep else {
      inFlight = nil
      return .skipped
    }
    let isLocal = localIdentifiers.contains(message.notificationIdentifier)
    if !isLocal, loaded.suppresses(message) {
      inFlight = nil
      await discard(message, ref: ref, repeating: repeatsLeft != nil)
      return .skipped
    }
    if await holdBack(loaded, for: message, exempt: isLocal) {
      inFlight = nil
      return .skipped
    }
    let config = applyingDismissOverride(to: loaded, for: message)
    let content = DeliveryPolicy.content(for: message, config: config)
    do throws(NtfyError) {
      try await poster.post(content)
    } catch {
      log("notification \(content.identifier) not posted: \(error)")
      let overtaken = inFlight?.fate != .keep
      inFlight = nil
      return overtaken ? .skipped : .failed
    }
    let fate = inFlight?.fate ?? .keep
    inFlight = nil
    guard fate == .keep else {
      if fate == .withdrawn { await poster.remove(identifiers: [content.identifier]) }
      await settleReminder(ref)
      return .posted
    }
    startTimers(for: content, message: message, repeatsLeft: repeatsLeft, config: config)
    if repeatsLeft == nil {
      await markNotified(ref)
      await settleReminder(ref)
    }
    return .posted
  }

  /// A suppressed message is settled without a notification: marked notified (a re-alert already
  /// was) and, if it was a snoozed reminder, cleared.
  private func discard(_ message: NtfyMessage, ref: MessageRef, repeating: Bool) async {
    log("notification \(message.notificationIdentifier) suppressed by the topic settings")
    if !repeating { await markNotified(ref) }
    await settleReminder(ref)
  }

  private func postSummary(
    count: Int, oldestTopic: String, covers: [MessageRef], cause: MissedSummaryCause
  ) async -> Outcome {
    if await holdBack(await currentConfig(), for: nil) { return .skipped }
    do throws(NtfyError) {
      try await poster.postMissedSummary(count: count, oldestTopic: oldestTopic, cause: cause)
    } catch {
      log("missed-message summary not posted: \(error)")
      return .failed
    }
    for ref in covers { await markNotified(ref) }
    return .posted
  }
}
