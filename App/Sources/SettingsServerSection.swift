import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The result of a connection test, as the Server section and the onboarding show it.
struct ServerTestResultView: View {
  let state: ServerTestState

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case .testing:
      ProgressView("Testing the connection…")
        .controlSize(.small)
    case .finished(let result):
      Label(
        result.explanation,
        systemImage: state.isSaved ? "checkmark.circle.fill" : "xmark.octagon.fill"
      )
      .foregroundStyle(state.isSaved ? .green : .red)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct SettingsServerSection: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      Section("Connection") {
        LabeledContent("Status", value: model.app.connection.title)
        TextField(settingLabel(.serverURL), text: $model.urlText, prompt: Text("ntfy.example.com"))
          .autocorrectionDisabled()
          .help(settingCommandHint(.serverURL))
        SecureField(
          settingLabel(.token), text: $model.tokenText, prompt: Text(model.maskedTokenPlaceholder)
        )
        .help(settingCommandHint(.token))
        HStack {
          Button("Test and save") { Task { await model.testAndSave() } }
            .disabled(model.serverTest.isTesting || model.urlText.isEmpty)
          ServerTestResultView(state: model.serverTest)
        }
        Text(
          "The token is kept in the Keychain and never shown again. Leave it empty to keep the saved one."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Section("Plain http") {
        Toggle(
          settingLabel(.allowInsecure),
          isOn: Binding(
            get: { model.config.allowInsecure },
            set: { value in Task { await model.setAllowInsecure(value) } })
        )
        .help(settingCommandHint(.allowInsecure))
        Label(
          "Without https the token is sent unencrypted and anyone on the network path can read it. "
            + "Only turn this on for a server on a network you trust.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout)
        .foregroundStyle(.orange)
      }
    }
    .formStyle(.grouped)
  }
}
