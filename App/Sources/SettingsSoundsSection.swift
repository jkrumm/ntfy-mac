import NtfyAppLogic
import NtfyCore
import SwiftUI

/// Sound and dismiss time per priority as one table: a header row once, then one row per
/// priority, so every control sits in the same column in every row.
struct SettingsSoundsSection: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section {
        // Full labels while the window is wide enough, else the short ones; one choice for the
        // whole table, so the rows never disagree.
        ViewThatFits(in: .horizontal) {
          table(compact: false).fixedSize(horizontal: true, vertical: false)
          table(compact: true).fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } footer: {
        Text(
          "A notification goes away on its own after the dismiss time. \u{201C}Keep\u{201D} leaves it "
            + "on screen until you act."
        )
      }
      Section {
        Button("Reset all to defaults") { Task { await model.resetSoundsAndDismiss() } }
          .help("Terminal: ntfy-mac config sounds reset, ntfy-mac config dismiss reset")
      }
    }
    .formStyle(.grouped)
  }

  private func table(compact: Bool) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
      GridRow {
        header("Priority")
        header("Sound")
          .gridCellColumns(2)
        header("Dismiss")
          .gridCellColumns(2)
        Color.clear.frame(width: 20, height: 1)
      }
      Divider().gridCellUnsizedAxes(.horizontal)
      ForEach(SettingsModel.priorities.reversed(), id: \.self) { priority in
        PriorityRow(model: model, priority: priority, compact: compact)
      }
    }
    .padding(.vertical, 4)
  }

  private func header(_ title: String) -> some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
  }
}

/// One row of the table: priority, sound with its preview, "Keep until I act" and the dismiss
/// time, and a reset that only shows once the row differs from the default.
private struct PriorityRow: View {
  let model: SettingsModel
  let priority: Int
  let compact: Bool
  private static let defaultSeconds = 8.0

  var body: some View {
    GridRow {
      Text(SettingsModel.priorityTitle(priority))
        .fontWeight(.medium)
        .frame(width: 76, alignment: .leading)
      Picker(settingLabel(.sounds), selection: sound) {
        Text("Silent").tag(SoundChoice.silent)
        ForEach(model.soundOptions(for: priority), id: \.self) { name in
          Text(name).tag(SoundChoice.named(name))
        }
      }
      .labelsHidden()
      .frame(width: 104)
      .help(settingCommandHint(.sounds))
      Button {
        model.previewSound(for: priority)
      } label: {
        Image(systemName: "play.circle")
      }
      .buttonStyle(.borderless)
      .help("Preview the sound")
      Toggle(compact ? "Keep" : "Keep until I act", isOn: keep)
        .toggleStyle(.checkbox)
        .fixedSize()
        .help("Keep the notification until you act on it. \(settingCommandHint(.dismiss))")
      dismissTime
        .frame(width: 92, alignment: .leading)
      Button {
        Task { await model.resetPriority(priority) }
      } label: {
        Image(systemName: "arrow.counterclockwise")
      }
      .buttonStyle(.borderless)
      .help("Back to the default for this priority")
      .opacity(model.isCustomized(priority) ? 1 : 0)
      .disabled(!model.isCustomized(priority))
      .frame(width: 20)
    }
  }

  /// "after 8 s" with its stepper while the notification goes away on its own; empty when kept,
  /// so the column keeps its place.
  @ViewBuilder private var dismissTime: some View {
    if let seconds = model.dismissSeconds(for: priority) {
      Stepper(
        value: Binding(
          get: { seconds },
          set: { value in Task { await model.setDismiss(seconds: value, for: priority) } }),
        in: 1...3600, step: seconds < 30 ? 1 : 5
      ) {
        Text("after \(Int(seconds)) s").monospacedDigit()
      }
    } else {
      Color.clear.frame(height: 1)
    }
  }

  private var sound: Binding<SoundChoice> {
    Binding(
      get: { model.soundChoice(for: priority) },
      set: { value in Task { await model.setSound(value, for: priority) } })
  }

  private var keep: Binding<Bool> {
    Binding(
      get: { model.dismissSeconds(for: priority) == nil },
      set: { keep in
        Task { await model.setDismiss(seconds: keep ? nil : Self.defaultSeconds, for: priority) }
      })
  }
}
