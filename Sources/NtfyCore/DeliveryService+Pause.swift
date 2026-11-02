import Foundation

extension DeliveryService {
  /// True while the config pauses notifications. The held-back message stays unnotified in the
  /// history, and a task is armed to reconcile once the pause is over.
  func holdBack(_ config: Config) -> Bool {
    guard let until = config.pausedUntil, until > clock.now() else { return false }
    heldBack = true
    armResume(at: until)
    return true
  }

  private func armResume(at until: Date) {
    guard !stopped else { return }
    resumeTask?.cancel()
    let wait = until.timeIntervalSince(clock.now())
    resumeTask = Task {
      do { try await clock.sleep(for: .seconds(wait)) } catch { return }
      await self.resumeIfPauseOver()
    }
  }

  /// Reconciles once when something was held back and the pause is over. A pause that was
  /// extended in the meantime arms the next wake-up instead.
  func resumeIfPauseOver() async {
    guard heldBack, !stopped else { return }
    let config = await currentConfig()
    if holdBack(config) { return }
    heldBack = false
    resumeTask = nil
    await reconcile()
  }
}

extension DeliveryService {
  /// The config as this one message sees it: its `deliverLocal` auto-dismiss, if any, in place
  /// of the configured one for its priority.
  func applyingDismissOverride(to config: Config, for message: NtfyMessage) -> Config {
    guard let seconds = dismissOverrides.removeValue(forKey: message.notificationIdentifier) else {
      return config
    }
    var result = config
    result.dismiss[message.priority.rawValue] = seconds
    return result
  }
}
