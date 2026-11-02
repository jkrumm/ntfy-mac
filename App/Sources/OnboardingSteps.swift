import NtfyAppLogic
import SwiftUI

struct OnboardingServerStep: View {
  @Bindable var model: OnboardingModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Connect to your ntfy server. The token stays in the Keychain.")
        .foregroundStyle(.secondary)
      TextField("Server URL", text: $model.urlText, prompt: Text("ntfy.example.com"))
        .autocorrectionDisabled()
      SecureField("Access token", text: $model.tokenText, prompt: Text("tk_..."))
      HStack {
        Button("Test connection") { Task { await model.testConnection() } }
          .disabled(!model.canTest)
        ServerTestResultView(state: model.serverTest)
      }
    }
  }
}

struct OnboardingNotificationsStep: View {
  let model: OnboardingModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("macOS decides whether ntfy-mac may notify you, so it has to be allowed there.")
        .foregroundStyle(.secondary)
      PermissionStatusView(flow: model.permission)
      Divider()
      HStack {
        Button("Send a test notification") {
          Task { await model.permission.sendTestNotification() }
        }
        switch model.permission.testState {
        case .idle: EmptyView()
        case .sent:
          Label("Sent. Did it arrive?", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .failed(let reason):
          Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
      }
    }
  }
}

struct OnboardingLoginStep: View {
  @Bindable var model: OnboardingModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "ntfy-mac lives in the menu bar. Start it when you log in so messages do not wait for you."
      )
      .foregroundStyle(.secondary)
      Toggle("Launch ntfy-mac at login", isOn: $model.launchAtLogin)
      if let error = model.loginError {
        Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
      }
    }
  }
}
