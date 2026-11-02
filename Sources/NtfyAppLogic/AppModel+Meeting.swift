import Foundation
import NtfyCore

extension AppModel {
  /// Says you are presenting (or not): notifications are held back like in a detected meeting,
  /// for `duration` seconds (an hour unless told otherwise, so it cannot be forgotten). What was
  /// held shows as one summary afterwards. A failed write shows in `presentingError`.
  public func setPresenting(
    _ presenting: Bool, for duration: TimeInterval = MeetingSettings.defaultPresentingDuration
  ) async {
    let until: Date? = presenting ? clock.now().addingTimeInterval(duration) : nil
    do throws(NtfyError) {
      try await config.update { $0.meeting.presentingUntil = until }
      presentingError = nil
    } catch {
      presentingError = "Presenting could not be changed: \(error)"
      log("presenting not stored: \(error)")
    }
    await refresh()
    await handles?.delivery.recheckHold()
  }
}
