import Foundation
import NtfyCore

/// A sound as the picker offers it.
public enum SoundChoice: Sendable, Hashable {
  case silent
  case named(String)
}

extension SettingsModel {
  public static let priorities = Array(Priority.range)

  /// What plays for the priority now: the override, else the built-in default.
  public func soundChoice(for priority: Int) -> SoundChoice {
    PriorityProfile(priority: priority, config: config).sound.map(SoundChoice.named) ?? .silent
  }

  /// The sound names to pick from; the current one stays in the list when it was removed from
  /// disk.
  public func soundOptions(for priority: Int) -> [String] {
    guard case .named(let current) = soundChoice(for: priority), !soundNames.contains(current)
    else { return soundNames }
    return (soundNames + [current]).sorted()
  }

  public func setSound(_ choice: SoundChoice, for priority: Int) async {
    let sound: ConfigSound
    switch choice {
    case .silent: sound = .silent
    case .named(let name): sound = .named(name)
    }
    await write { $0.sounds[priority] = sound }
  }

  /// Plays the sound for the priority; silent plays nothing.
  public func previewSound(for priority: Int) {
    guard case .named(let name) = soundChoice(for: priority) else { return }
    preview.play(name)
  }

  /// Seconds until the notification of this priority goes away; nil keeps it until the user acts.
  public func dismissSeconds(for priority: Int) -> Double? {
    PriorityProfile(priority: priority, config: config).dismissAfter.map(Self.seconds)
  }

  /// `nil` keeps the notification; a number below 1 is 1.
  public func setDismiss(seconds: Double?, for priority: Int) async {
    let stored = seconds.map { max($0.isFinite ? $0 : 1, 1) } ?? 0
    await write { $0.dismiss[priority] = stored }
  }

  /// The sound or the dismiss time of this priority differs from the default.
  public func isCustomized(_ priority: Int) -> Bool {
    config.sounds[priority] != nil || config.dismiss[priority] != nil
  }

  /// Back to the defaults for one priority.
  public func resetPriority(_ priority: Int) async {
    await write {
      $0.sounds[priority] = nil
      $0.dismiss[priority] = nil
    }
  }

  /// Like `config sounds reset` and `config dismiss reset` together.
  public func resetSoundsAndDismiss() async {
    await write {
      $0.sounds = [:]
      $0.dismiss = [:]
    }
  }

  private static func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }
}

extension SettingsModel {
  /// `5 (urgent)`, as `config sounds` prints the row.
  public static func priorityTitle(_ priority: Int) -> String {
    "\(priority) (\(Priority(clamping: priority).label))"
  }
}
