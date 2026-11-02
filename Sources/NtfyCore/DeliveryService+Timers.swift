import Foundation

extension DeliveryService {
  /// Starts what runs after a successful post: the auto-dismiss and the re-alert chain.
  func startTimers(
    for content: NotificationContent, message: NtfyMessage, repeatsLeft: Int?, config: Config
  ) {
    timers.cancel(identifier: content.identifier)
    if let after = content.dismissAfter {
      scheduleDismiss(
        identifier: content.identifier, ref: content.messageRef, after: after.timeInterval)
    }
    guard content.requiresAcknowledge else { return }
    scheduleRealert(
      message, repeatsLeft: repeatsLeft ?? config.reAlertMaxRepeats,
      interval: TimeInterval(config.reAlertIntervalSeconds))
  }

  func scheduleDismiss(identifier: String, ref: MessageRef, after: TimeInterval) {
    guard !stopped else { return }
    let key = DeliveryTimers.Key(kind: .dismiss, identifier: identifier)
    timers.schedule(key, ref: ref, after: .seconds(after), clock: clock) { generation in
      await self.dismissFired(key, generation: generation)
    }
  }

  func scheduleRealert(_ message: NtfyMessage, repeatsLeft: Int, interval: TimeInterval) {
    guard !stopped, repeatsLeft > 0 else { return }
    let key = DeliveryTimers.Key(kind: .realert, identifier: message.notificationIdentifier)
    let ref = MessageRef(topic: message.topic, id: message.id)
    timers.schedule(key, ref: ref, after: .seconds(interval), clock: clock) { generation in
      await self.realertFired(message, key: key, generation: generation, repeatsLeft: repeatsLeft)
    }
  }

  private func dismissFired(_ key: DeliveryTimers.Key, generation: Int) async {
    guard timers.finish(key, generation: generation) else { return }
    await poster.remove(identifiers: [key.identifier])
  }

  /// Queues one more post of the message. The config is read now, so switching re-alert off
  /// stops the chain at its next tick; the post's own success schedules the tick after it.
  private func realertFired(
    _ message: NtfyMessage, key: DeliveryTimers.Key, generation: Int, repeatsLeft: Int
  ) async {
    guard timers.isCurrent(key, generation: generation) else { return }
    let config = await currentConfig()
    guard timers.finish(key, generation: generation), config.reAlert, !stopped else { return }
    queue.enqueue(.message(message, repeatsLeft: repeatsLeft - 1))
    startDraining()
  }

  // MARK: Reminders

  func pollReminders() async {
    while !Task.isCancelled {
      do { try await clock.sleep(for: Self.reminderPollInterval) } catch { return }
      await fireDueReminders()
    }
  }

  /// Shows every reminder that came due again and clears it, so it fires once. A reminder is
  /// cleared when queued, not when shown: a failed post leaves the message in history, unread.
  func fireDueReminders() async {
    guard !stopped, !isFiringReminders else { return }
    isFiringReminders = true
    defer { isFiringReminders = false }
    do throws(NtfyError) {
      for stored in try await inbox.dueReminders(now: clock.now()) {
        deliver(stored.message)
        try await inbox.clearReminder(topic: stored.message.topic, id: stored.message.id)
      }
    } catch {
      log("reminders not fired: \(error)")
    }
  }
}
