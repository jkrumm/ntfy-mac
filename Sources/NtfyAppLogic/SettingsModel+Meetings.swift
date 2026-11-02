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

  /// The manual override, until switched off.
  public func setPresenting(_ presenting: Bool) async {
    await write { $0.meeting.presentingUntil = presenting ? PauseWindow.indefinite : nil }
  }

  /// The override is on.
  public var isPresenting: Bool { config.meeting.isPresenting(at: Date()) }
}
