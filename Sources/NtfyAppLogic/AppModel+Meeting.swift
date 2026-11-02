import Foundation
import NtfyCore

/// A `PipelineSource` that also has the meeting detection, which outlives pipeline rebuilds. The
/// app root implements it; the model looks for it on its source.
public protocol MeetingSource: Sendable {
  var meetingState: any MeetingStateProviding { get }
}

extension AppModel {
  /// Says you are presenting (or not): notifications are held back like in a detected meeting,
  /// for `duration` seconds or, without one, until it is switched off. What was held shows as
  /// one summary afterwards.
  public func setPresenting(_ presenting: Bool, for duration: TimeInterval? = nil) async {
    let until: Date? =
      presenting
      ? duration.map { clock.now().addingTimeInterval($0) } ?? PauseWindow.indefinite : nil
    do throws(NtfyError) {
      try await config.update { $0.meeting.presentingUntil = until }
    } catch {
      log("presenting not stored: \(error)")
    }
    await refresh()
    await handles?.delivery.recheckHold()
  }
}
