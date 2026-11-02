import Foundation
import NtfyCore

extension SettingsModel {
  // MARK: Meetings

  public func setMeetingMode(_ mode: MeetingMode) async {
    await write { $0.meeting.mode = mode }
  }

  public func setMeetingUrgentBypass(_ bypass: Bool) async {
    await write { $0.meeting.urgentBypass = bypass }
  }

  /// The manual override, for an hour or until switched off. A failed write shows in `notice`.
  public func setPresenting(_ presenting: Bool) async {
    let until = app.clock.now().addingTimeInterval(MeetingSettings.defaultPresentingDuration)
    await write { $0.meeting.presentingUntil = presenting ? until : nil }
  }

  /// The override is on.
  public var isPresenting: Bool { config.meeting.isPresenting(at: app.clock.now()) }
}
