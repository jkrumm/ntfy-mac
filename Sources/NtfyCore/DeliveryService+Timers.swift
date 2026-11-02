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
      await resumeIfPauseOver()
      await fireDueReminders()
    }
  }

  /// Queues every reminder that came due. A reminder is cleared in the history only after its
  /// post succeeded (`settleReminder`); a failed or interrupted post leaves it due, so the next
  /// tick or boot fires it again. One whose clearing failed is not shown twice: it is only
  /// cleared again.
  func fireDueReminders() async {
    guard !stopped, !isFiringReminders else { return }
    isFiringReminders = true
    defer { isFiringReminders = false }
    let due: [StoredMessage]
    do throws(NtfyError) {
      due = try await inbox.dueReminders(now: clock.now())
    } catch {
      log("reminders not read: \(error)")
      return
    }
    for stored in due {
      let ref = MessageRef(topic: stored.message.topic, id: stored.message.id)
      if unclearedReminders.contains(ref) {
        await clearReminder(ref)
        continue
      }
      guard !queuedReminders.contains(ref) else { continue }
      queuedReminders.insert(ref)
      deliver(stored.message)
    }
  }

  /// Called when a post of `ref` went through: clears its reminder if it was one.
  func settleReminder(_ ref: MessageRef) async {
    guard queuedReminders.remove(ref) != nil else { return }
    await clearReminder(ref)
  }

  /// Forgets reminders whose post will not happen (given up, superseded, withdrawn).
  func dropAbandonedReminders() {
    queuedReminders = queuedReminders.filter { isPending($0) }
  }

  private func clearReminder(_ ref: MessageRef) async {
    do throws(NtfyError) {
      try await inbox.clearReminder(topic: ref.topic, id: ref.id)
      unclearedReminders.remove(ref)
    } catch {
      unclearedReminders.insert(ref)
      log("reminder \(ref.topic)/\(ref.id) not cleared: \(error)")
    }
  }
}
