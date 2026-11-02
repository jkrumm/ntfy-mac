import NtfyAppLogic
import NtfyCore
import SwiftUI

struct SettingsGeneralSection: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section("Startup") {
        Toggle(
          settingLabel(.loginItem),
          isOn: Binding(
            get: { model.loginItem.isEnabled || model.loginItem == .requiresApproval },
            set: { value in Task { await model.setLaunchAtLogin(value) } })
        )
        .help(settingCommandHint(.loginItem))
        if let note = model.loginItemNote {
          Text(note).font(.callout).foregroundStyle(.secondary)
        }
      }
      Section(settingLabel(.pause)) {
        if model.app.pausedUntil == nil {
          Text("Notifications are on. Pause them from the menu bar.")
            .foregroundStyle(.secondary)
        } else {
          HStack {
            Text(
              model.app.isPausedIndefinitely
                ? "Paused until you resume"
                : "Paused until \(model.app.pausedUntil?.formatted(.dateTime.hour().minute()) ?? "")"
            )
            Spacer()
            Button("Resume") { Task { await model.resume() } }
              .help(settingCommandHint(.pause))
          }
        }
      }
      Section(settingLabel(.notificationPermission)) {
        PermissionStatusView(flow: model.permission)
      }
      Section("About") {
        LabeledContent("Version", value: model.appVersion)
        Button("Set up again…") { model.setUpAgain() }
      }
    }
    .formStyle(.grouped)
  }
}
