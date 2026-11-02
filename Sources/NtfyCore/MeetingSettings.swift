import Foundation

/// What the app does when it detects a video meeting.
public enum MeetingMode: String, Sendable, CaseIterable, Hashable {
  /// Nothing is detected and nothing is held back. The default.
  case off
  /// Banners and sounds are held back while a meeting is detected; the messages are stored and
  /// shown afterwards as one summary.
  case pause
}

/// The `meeting` group of the config file.
///
/// `presentingUntil` is the manual "I am presenting" override: while it is in the future, a
/// meeting is assumed whatever the detection says and whatever `mode` is.
public struct MeetingSettings: Sendable, Hashable {
  public var mode: MeetingMode
  /// Messages at priority 5 get through, as with quiet hours.
  public var urgentBypass: Bool
  /// `PauseWindow.indefinite` means until it is switched off.
  public var presentingUntil: Date?

  public init(
    mode: MeetingMode = .off, urgentBypass: Bool = true, presentingUntil: Date? = nil
  ) {
    self.mode = mode
    self.urgentBypass = urgentBypass
    self.presentingUntil = presentingUntil
  }

  private enum Key {
    static let mode = "mode"
    static let urgentBypass = "urgentBypass"
    static let presentingUntil = "presentingUntil"
  }

  /// Whether the manual override is on at `now`.
  public func isPresenting(at now: Date) -> Bool {
    presentingUntil.map { $0 > now } ?? false
  }

  /// Reads the `meeting` object; wrong-typed or unknown fields read as their default.
  init(value: ConfigValue?) {
    let object = value?.objectValue ?? [:]
    var urgentBypass = true
    if case .bool(let flag)? = object[Key.urgentBypass] { urgentBypass = flag }
    self.init(
      mode: object[Key.mode]?.stringValue.flatMap(MeetingMode.init(rawValue:)) ?? .off,
      urgentBypass: urgentBypass,
      presentingUntil: object[Key.presentingUntil]?.stringValue.flatMap(Config.parseDate))
  }

  /// The JSON to write, or nil when every field is at its default.
  var configValue: ConfigValue? {
    var object: [String: ConfigValue] = [:]
    if mode != .off { object[Key.mode] = .string(mode.rawValue) }
    if !urgentBypass { object[Key.urgentBypass] = .bool(false) }
    if let presentingUntil {
      object[Key.presentingUntil] = .string(Config.formatDate(presentingUntil))
    }
    return object.isEmpty ? nil : .object(object)
  }
}
