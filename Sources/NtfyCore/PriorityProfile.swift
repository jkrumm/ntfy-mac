/// How loudly macOS may interrupt for a notification.
public enum InterruptionLevel: Sendable, Hashable {
  case passive, active, timeSensitive
}

/// The delivery behaviour of one priority: the 1.x table plus the user's overrides.
public struct PriorityProfile: Sendable, Hashable {
  /// System sound name; nil plays none.
  public let sound: String?
  public let interruption: InterruptionLevel
  public let relevance: Double
  /// Nil keeps the notification until the user acts.
  public let dismissAfter: Duration?

  public init(
    sound: String?, interruption: InterruptionLevel, relevance: Double, dismissAfter: Duration?
  ) {
    self.sound = sound
    self.interruption = interruption
    self.relevance = relevance
    self.dismissAfter = dismissAfter
  }

  private static func base(for priority: Int) -> PriorityProfile {
    switch priority {
    case 5:
      PriorityProfile(
        sound: "Ping", interruption: .timeSensitive, relevance: 1.0, dismissAfter: nil)
    case 4:
      PriorityProfile(
        sound: "Ping", interruption: .timeSensitive, relevance: 0.75, dismissAfter: nil)
    case 2:
      PriorityProfile(
        sound: "Tink", interruption: .active, relevance: 0.25, dismissAfter: .seconds(5))
    case 1:
      PriorityProfile(
        sound: "Tink", interruption: .active, relevance: 0.0, dismissAfter: .seconds(4))
    default:
      PriorityProfile(
        sound: "Pop", interruption: .active, relevance: 0.5, dismissAfter: .seconds(8))
    }
  }

  /// The profile for `priority` with `config.sounds` and `config.dismiss` applied.
  /// A priority outside `1...5` behaves like 3.
  public init(priority: Int, config: Config = Config()) {
    let base = Self.base(for: priority)
    var sound = base.sound
    var dismissAfter = base.dismissAfter
    switch config.sounds[priority] {
    case .silent?: sound = nil
    case .named(let name)?: sound = name
    case nil: break
    }
    if let seconds = config.dismiss[priority] {
      dismissAfter = seconds > 0 ? .seconds(seconds) : nil
    }
    self.init(
      sound: sound, interruption: base.interruption, relevance: base.relevance,
      dismissAfter: dismissAfter)
  }
}
