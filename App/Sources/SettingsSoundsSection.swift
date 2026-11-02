import NtfyAppLogic
import NtfyCore
import SwiftUI

struct SettingsSoundsSection: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section {
        ForEach(SettingsModel.priorities.reversed(), id: \.self) { priority in
          PriorityRowView(model: model, priority: priority)
        }
      } footer: {
        Text(
          "A notification goes away on its own after the dismiss time; \u{201C}Keep\u{201D} leaves it until you act."
        )
      }
      Section {
        Button("Reset all to defaults") { Task { await model.resetSoundsAndDismiss() } }
          .help("Terminal: ntfy-mac config sounds reset, ntfy-mac config dismiss reset")
      }
    }
    .formStyle(.grouped)
  }
}

private struct PriorityRowView: View {
  let model: SettingsModel
  let priority: Int
  private static let defaultSeconds = 8.0

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(SettingsModel.priorityTitle(priority)).fontWeight(.semibold)
        Spacer()
        if model.isCustomized(priority) {
          Button("Reset") { Task { await model.resetPriority(priority) } }
        }
      }
      HStack {
        Picker(settingLabel(.sounds), selection: sound) {
          Text("Silent").tag(SoundChoice.silent)
          ForEach(model.soundOptions(for: priority), id: \.self) { name in
            Text(name).tag(SoundChoice.named(name))
          }
        }
        .help(settingCommandHint(.sounds))
        Button {
          model.previewSound(for: priority)
        } label: {
          Image(systemName: "play.circle")
        }
        .buttonStyle(.borderless)
        .help("Preview the sound")
      }
      HStack {
        Toggle("Keep until I act", isOn: keep)
        if let seconds = model.dismissSeconds(for: priority) {
          Stepper(
            "Dismiss after \(Int(seconds)) s",
            value: Binding(
              get: { seconds },
              set: { value in Task { await model.setDismiss(seconds: value, for: priority) } }),
            in: 1...3600, step: seconds < 30 ? 1 : 5)
        }
      }
      .help(settingCommandHint(.dismiss))
    }
    .padding(.vertical, 2)
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
