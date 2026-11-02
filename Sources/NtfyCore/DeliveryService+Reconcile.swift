import Foundation

extension DeliveryService {
  /// Settles what an earlier run left open. The composition root calls it once after `start`.
  ///
  /// 1. Stored messages that were never shown go through `announceMissed`; one that is skipped
  ///    silently is marked notified so it is not reconsidered at every boot.
  /// 2. Unacknowledged messages at or above the re-alert threshold and younger than
  ///    `reAlertResumeLimit` resume re-alerting, with a full repeat budget.
  /// 3. Delivered notifications whose auto-dismiss time has passed are removed; the others get
  ///    a timer for the rest of it.
  /// 4. Reminders that came due fire.
  public func reconcile() async {
    guard !stopped else { return }
    let config = await currentConfig()
    await announceUnnotified()
    await resumeRealerts(config)
    await expireDelivered(config)
    await fireDueReminders()
  }

  private func announceUnnotified() async {
    do throws(NtfyError) {
      var rows: [NtfyMessage] = []
      var pages = 0
      while true {
        let page = try await history.unnotified(limit: Self.reconcileLimit, offset: rows.count)
        pages += 1
        rows += page
        if page.count < Self.reconcileLimit { break }
      }
      if pages > 1 { log("reconcile read \(rows.count) unnotified messages in \(pages) pages") }
      await announceMissed(rows)
    } catch {
      log("unnotified messages not read: \(error)")
    }
  }

  private func resumeRealerts(_ config: Config) async {
    guard config.reAlert else { return }
    let threshold = Priority(clamping: config.reAlertMinPriority)
    let rows: [StoredMessage]
    do throws(NtfyError) {
      rows = try await inbox.unacknowledged(minPriority: threshold)
    } catch {
      log("unacknowledged messages not read: \(error)")
      return
    }
    let now = clock.now()
    for stored in rows where stored.notifiedAt != nil {
      guard now.timeIntervalSince(stored.message.time) < Self.reAlertResumeLimit else { continue }
      let key = DeliveryTimers.Key(
        kind: .realert, identifier: stored.message.notificationIdentifier)
      guard !timers.has(key) else { continue }
      scheduleRealert(
        stored.message, repeatsLeft: config.reAlertMaxRepeats,
        interval: TimeInterval(config.reAlertIntervalSeconds))
    }
  }

  private func expireDelivered(_ config: Config) async {
    let delivered = await poster.deliveredIdentifiers()
    guard !delivered.isEmpty else { return }
    let now = clock.now()
    var expired: [String] = []
    var found = Set<String>()
    var offset = 0
    var pages = 0
    scan: while true {
      let rows: [StoredMessage]
      do throws(NtfyError) {
        rows = try await inbox.entries(HistoryQuery(limit: Self.reconcileLimit, offset: offset))
      } catch {
        log("history not read: \(error)")
        break
      }
      pages += 1
      offset += rows.count
      for stored in rows {
        let identifier = stored.message.notificationIdentifier
        guard delivered.contains(identifier) else { continue }
        found.insert(identifier)
        if let gone = expire(stored, config: config, now: now) { expired.append(gone) }
        if found.count == delivered.count { break scan }
      }
      if rows.count < Self.reconcileLimit { break }
    }
    if pages > 1 { log("reconcile read \(offset) history rows in \(pages) pages") }
    if !expired.isEmpty { await poster.remove(identifiers: expired) }
  }

  /// Schedules the auto-dismiss of a delivered notification for the rest of its time, or returns
  /// its identifier when that time is already over.
  private func expire(_ stored: StoredMessage, config: Config, now: Date) -> String? {
    let identifier = stored.message.notificationIdentifier
    guard let shownAt = stored.notifiedAt else { return nil }
    let profile = PriorityProfile(priority: stored.message.priority.rawValue, config: config)
    guard let after = profile.dismissAfter else { return nil }
    let remaining = shownAt.addingTimeInterval(after.timeInterval).timeIntervalSince(now)
    if remaining <= 0 { return identifier }
    let ref = MessageRef(topic: stored.message.topic, id: stored.message.id)
    scheduleDismiss(identifier: identifier, ref: ref, after: remaining)
    return nil
  }
}
