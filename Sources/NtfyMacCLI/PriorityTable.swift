import Foundation
import NtfyCore

/// One priority's effective sound and auto-dismiss, and whether the user overrode them.
struct PriorityRow: Encodable, Sendable, Hashable {
  let priority: Int
  let label: String
  /// Nil when silent.
  let sound: String?
  let silent: Bool
  let customSound: Bool
  /// 0 means never.
  let dismissSeconds: Double
  let customDismiss: Bool

  init(priority: Int, config: Config) {
    let profile = PriorityProfile(priority: priority, config: config)
    self.priority = priority
    label = Self.label(priority)
    sound = profile.sound
    silent = profile.sound == nil
    customSound = config.sounds[priority] != nil
    dismissSeconds = profile.dismissAfter.map(Self.seconds) ?? 0
    customDismiss = config.dismiss[priority] != nil
  }

  static func label(_ priority: Int) -> String {
    switch priority {
    case 5: "urgent"
    case 4: "high"
    case 3: "default"
    case 2: "low"
    default: "min"
    }
  }

  var title: String { "\(priority) (\(label))" }
  var soundText: String { sound ?? "(silent)" }
  var dismissText: String {
    dismissSeconds == 0 ? "never" : "\(Self.format(dismissSeconds))s"
  }

  private static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
  }

  private static func format(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
  }
}

/// The five rows, urgent first, as `config` prints them.
struct PriorityTable: Encodable, Sendable {
  let priorities: [PriorityRow]

  init(config: Config) {
    priorities = Priority.range.reversed().map { PriorityRow(priority: $0, config: config) }
  }

  private func padded(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
  }

  func soundsText() -> String {
    var lines = ["Notification sounds", ""]
    lines.append("  Priority      Sound         Source")
    lines.append("  ────────────  ────────────  ──────")
    for row in priorities {
      lines.append(
        "  \(padded(row.title, 14))\(padded(row.soundText, 14))"
          + (row.customSound ? "custom" : "default"))
    }
    lines += [
      "", "Change with: ntfy-mac config sounds set <priority> <sound>",
      "Reset all:   ntfy-mac config sounds reset",
      "List sounds: ntfy-mac config sounds list",
      "Test:        ntfy-mac notify -m \"test\" -p <priority>",
    ]
    return lines.joined(separator: "\n")
  }

  func dismissText() -> String {
    var lines = ["Auto-dismiss timing", ""]
    lines.append("  Priority      Dismiss       Source")
    lines.append("  ────────────  ────────────  ──────")
    for row in priorities {
      lines.append(
        "  \(padded(row.title, 14))\(padded(row.dismissText, 14))"
          + (row.customDismiss ? "custom" : "default"))
    }
    lines += [
      "", "Change with: ntfy-mac config dismiss set <priority> <seconds|never>",
      "Reset all:   ntfy-mac config dismiss reset",
      "Test:        ntfy-mac notify -m \"test\" -p <priority>",
    ]
    return lines.joined(separator: "\n")
  }

  func overviewText() -> String {
    var lines = ["Notification configuration", ""]
    lines.append("  Priority      Sound         Dismiss")
    lines.append("  ────────────  ────────────  ────────────")
    for row in priorities {
      let sound = row.soundText + (row.customSound ? "*" : "")
      let dismiss = row.dismissText + (row.customDismiss ? "*" : "")
      lines.append("  \(padded(row.title, 14))\(padded(sound, 14))\(dismiss)")
    }
    lines += [
      "", "  * = custom override", "", "Commands:",
      "  ntfy-mac config sounds              Manage notification sounds",
      "  ntfy-mac config dismiss             Manage auto-dismiss timing",
      "  ntfy-mac config get|set|reset <key> Change re-alert and security settings",
      "  ntfy-mac config topic               Mute, filter or decorate one topic",
      "  ntfy-mac config quiet-hours         Hold notifications back during a daily window",
      "  ntfy-mac notify -m \"test\" -p <1-5>  Test a priority level",
    ]
    return lines.joined(separator: "\n")
  }
}
