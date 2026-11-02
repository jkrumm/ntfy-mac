import Foundation

extension DeliveryService {
  /// True while the config holds notifications back: a manual pause, quiet hours or a meeting
  /// for a message they apply to (`message` nil stands for a summary, which has no single
  /// priority and is held by any quiet window or meeting). The held-back message stays
  /// unnotified in the history. A task is armed to reconcile once a timed hold is over; a
  /// meeting has no end time, so the meeting source's change signal wakes the service instead.
  /// `exempt` is for a local message, which neither quiet hours nor a meeting hold.
  func holdBack(_ config: Config, for message: NtfyMessage?, exempt: Bool = false) async -> Bool {
    let detected = await meeting?.current() ?? .inactive
    let now = clock.now()
    let quietEnd = quietHoldEnd(config, for: message, exempt: exempt, now: now)
    let meetingHeld = meetingHolds(
      config, detected: detected, for: message, exempt: exempt, now: now)
    let until = holdEnd(config, quietEnd: quietEnd, now: now)
    guard until != nil || meetingHeld else { return false }
    heldBack = true
    if quietEnd != nil { quietHeld = true }
    if meetingHeld { meetingHeldBack = true }
    if let wake = until ?? presentingEnd(config, now: now) { armResume(at: wake) }
    return true
  }

  /// The later of the pause end and the quiet-hours end, whichever hold applies; nil when none.
  private func holdEnd(_ config: Config, quietEnd: Date?, now: Date) -> Date? {
    let pauseEnd = config.pausedUntil.flatMap { $0 > now ? $0 : nil }
    return [pauseEnd, quietEnd].compactMap { $0 }.max()
  }

  private func quietHoldEnd(
    _ config: Config, for message: NtfyMessage?, exempt: Bool, now: Date
  ) -> Date? {
    let quiet = config.quietHours
    guard !exempt, quiet.contains(now, calendar: calendar) else { return nil }
    if quiet.urgentBypass, let message, message.priority == .max { return nil }
    return quiet.nextEnd(after: now, calendar: calendar)
  }

  private func meetingHolds(
    _ config: Config, detected: MeetingState, for message: NtfyMessage?, exempt: Bool, now: Date
  ) -> Bool {
    guard !exempt, config.meeting.effectiveState(detected: detected, at: now).isActive else {
      return false
    }
    return !(config.meeting.urgentBypass && message?.priority == .max)
  }

  /// When a timed "I am presenting" override ends, so the service looks again then.
  private func presentingEnd(_ config: Config, now: Date) -> Date? {
    guard let end = config.meeting.presentingUntil, end > now, !PauseWindow.isIndefinite(end)
    else { return nil }
    return end
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

  /// Reconciles once when something was held back and the hold is over. A pause that was
  /// extended, or quiet hours that were edited, in the meantime arm the next wake-up instead; a
  /// meeting that is still going on waits for the meeting source's next change. The wake-up runs
  /// on the injected clock, whose sleep keeps counting while the machine sleeps; the reminder
  /// poll is the backstop for a config edited to end the hold sooner.
  func resumeIfPauseOver() async {
    guard heldBack, !stopped else { return }
    let config = await currentConfig()
    let detected = await meeting?.current() ?? .inactive
    guard heldBack, !stopped else { return }
    let now = clock.now()
    let quietEnd = quietHoldEnd(config, for: nil, exempt: false, now: now)
    if let until = holdEnd(config, quietEnd: quietEnd, now: now) {
      armResume(at: until)
      return
    }
    if config.meeting.effectiveState(detected: detected, at: now).isActive {
      if let end = presentingEnd(config, now: now) { armResume(at: end) }
      return
    }
    let announcement: Announcement =
      meetingHeldBack
      ? .meetingSummary
      : !quietHeld ? .byAge : config.quietHours.digest ? .summary : .each
    heldBack = false
    quietHeld = false
    meetingHeldBack = false
    resumeTask = nil
    await reconcile(announcing: announcement)
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
