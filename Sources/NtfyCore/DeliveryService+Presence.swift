import Foundation

extension DeliveryService {
  func handlePresence(_ event: SystemEvent) async {
    switch event {
    case .screensDidSleep, .willSleep:
      guard attended else { return }
      attended = false
      trace("delivery: away, displays asleep")
    case .screensDidWake:
      await userReturned()
    case .didWake, .pathChanged, .screenLocked, .screenUnlocked:
      return
    }
  }

  /// Posts again what the user could not have seen: every unacknowledged message at or above the
  /// re-alert threshold whose notification was posted, or whose re-alert came due, while away.
  /// Each starts its chain again with a full budget, so being away never uses it up.
  private func userReturned() async {
    guard !attended else { return }
    attended = true
    let owed = owedWhileAway
    owedWhileAway = []
    trace("delivery: back, displays awake, \(owed.count) notification(s) owed")
    guard !owed.isEmpty, !stopped else { return }
    let config = await currentConfig()
    guard config.reAlert else { return }
    let rows: [StoredMessage]
    do throws(NtfyError) {
      rows = try await inbox.unacknowledged(
        minPriority: Priority(clamping: config.reAlertMinPriority))
    } catch {
      log("unacknowledged messages not read: \(error)")
      return
    }
    for stored in rows where owed.contains(stored.message.notificationIdentifier) {
      let message = stored.message
      let ref = MessageRef(topic: message.topic, id: message.id)
      guard !isPending(ref), !config.suppresses(message), !stopped else { continue }
      queue.enqueue(.message(message, repeatsLeft: nil))
    }
    startDraining()
  }
}
