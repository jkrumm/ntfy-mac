import NtfyAppLogic
import NtfyCore
import SwiftUI

struct SettingsReAlertSection: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section {
        Toggle(
          settingLabel(.reAlert),
          isOn: Binding(
            get: { model.config.reAlert }, set: { value in Task { await model.setReAlert(value) } })
        )
        .help(settingCommandHint(.reAlert))
        LabeledContent(settingLabel(.reAlertMinPriority)) {
          Picker(
            settingLabel(.reAlertMinPriority),
            selection: Binding(
              get: { model.config.reAlertMinPriority },
              set: { value in Task { await model.setReAlertMinPriority(value) } })
          ) {
            ForEach(SettingsModel.priorities.reversed(), id: \.self) { value in
              Text(SettingsModel.priorityTitle(value)).tag(value)
            }
          }
          .labelsHidden()
          .fixedSize()
        }
        .help(settingCommandHint(.reAlertMinPriority))
        LabeledContent(settingLabel(.reAlertIntervalSeconds)) {
          HStack {
            Text("\(model.config.reAlertIntervalSeconds) s").monospacedDigit()
            Stepper(
              "",
              value: Binding(
                get: { model.config.reAlertIntervalSeconds },
                set: { value in Task { await model.setReAlertInterval(seconds: value) } }),
              in: 10...86_400, step: 30
            )
            .labelsHidden()
          }
        }
        .help(settingCommandHint(.reAlertIntervalSeconds))
        LabeledContent(settingLabel(.reAlertMaxRepeats)) {
          HStack {
            Text("\(model.config.reAlertMaxRepeats)").monospacedDigit()
            Stepper(
              "",
              value: Binding(
                get: { model.config.reAlertMaxRepeats },
                set: { value in Task { await model.setReAlertMaxRepeats(value) } }),
              in: 0...100
            )
            .labelsHidden()
          }
        }
        .help(settingCommandHint(.reAlertMaxRepeats))
      } footer: {
        Text(model.reAlertSummary)
      }
    }
    .formStyle(.grouped)
  }
}

struct SettingsQuietHoursSection: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section {
        Toggle(
          settingLabel(.quietHoursEnabled),
          isOn: Binding(
            get: { model.config.quietHours.enabled },
            set: { value in Task { await model.setQuietHoursEnabled(value) } })
        )
        .help(settingCommandHint(.quietHoursEnabled))
        DatePicker(
          settingLabel(.quietHoursStart),
          selection: Binding(
            get: { model.date(for: model.config.quietHours.start) },
            set: { value in Task { await model.setQuietHoursStart(model.clockTime(from: value)) } }),
          displayedComponents: .hourAndMinute
        )
        .help(settingCommandHint(.quietHoursStart))
        DatePicker(
          settingLabel(.quietHoursEnd),
          selection: Binding(
            get: { model.date(for: model.config.quietHours.end) },
            set: { value in Task { await model.setQuietHoursEnd(model.clockTime(from: value)) } }),
          displayedComponents: .hourAndMinute
        )
        .help(settingCommandHint(.quietHoursEnd))
      } footer: {
        Text(
          "Messages that arrive inside the window are stored and not notified. The window may cross midnight."
        )
      }
      Section {
        Toggle(
          settingLabel(.quietHoursUrgentBypass),
          isOn: Binding(
            get: { model.config.quietHours.urgentBypass },
            set: { value in Task { await model.setUrgentBypass(value) } })
        )
        .help(settingCommandHint(.quietHoursUrgentBypass))
        Text("Urgent (priority 5) messages notify even inside the window.")
          .font(.callout).foregroundStyle(.secondary)
        Toggle(
          settingLabel(.quietHoursDigest),
          isOn: Binding(
            get: { model.config.quietHours.digest },
            set: { value in Task { await model.setDigest(value) } })
        )
        .help(settingCommandHint(.quietHoursDigest))
        Text("When the window ends, what was held shows as one summary instead of one by one.")
          .font(.callout).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

struct SettingsActionsSection: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section {
        Toggle(
          settingLabel(.allowPrivateNetworkActions),
          isOn: Binding(
            get: { model.config.allowPrivateNetworkActions },
            set: { value in Task { await model.setAllowPrivateNetworkActions(value) } })
        )
        .help(settingCommandHint(.allowPrivateNetworkActions))
      } footer: {
        Text(
          "A message can carry buttons that send an http request. By default ntfy-mac asks before "
            + "a button reaches a device on your own network, such as your router. "
            + "Turn this on only if you trust every topic you subscribe to."
        )
      }
    }
    .formStyle(.grouped)
  }
}
