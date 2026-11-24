import NtfyAppLogic
import NtfyCore
import SwiftUI

struct SettingsSummarySection: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      Section {
        Toggle(
          settingLabel(.summaryEnabled),
          isOn: Binding(
            get: { model.config.summary.enabled },
            set: { value in Task { await model.setSummaryEnabled(value) } })
        )
        .help(settingCommandHint(.summaryEnabled))
      } footer: {
        Text(
          "When you come back to the Mac, or open History after a while, one notification "
            + "summarizes what came in. A cheap model writes it through an Anthropic-compatible "
            + "endpoint you configure; without one, or when it fails, you get the counts per topic."
        )
      }
      Section("Endpoint") {
        TextField(
          settingLabel(.summaryEndpoint), text: $model.summaryEndpointText,
          prompt: Text("https://api.anthropic.com")
        )
        .autocorrectionDisabled()
        .onSubmit { Task { await model.commitSummaryEndpoint() } }
        .help(settingCommandHint(.summaryEndpoint))
        SecureField(
          settingLabel(.summaryKey), text: $model.summaryKeyText,
          prompt: Text(model.hasSummaryKey ? "Saved in the Keychain" : "sk-ant-...")
        )
        .onSubmit { Task { await model.saveSummaryKey() } }
        .help(settingCommandHint(.summaryKey))
        TextField(settingLabel(.summaryModel), text: $model.summaryModelText)
          .autocorrectionDisabled()
          .onSubmit { Task { await model.commitSummaryModel() } }
          .help(settingCommandHint(.summaryModel))
        HStack {
          Button("Save") {
            Task {
              await model.commitSummaryEndpoint()
              await model.commitSummaryModel()
              await model.saveSummaryKey()
            }
          }
          Button("Remove key") { Task { await model.clearSummaryKey() } }
            .disabled(!model.hasSummaryKey)
          Button("Test") { Task { await model.testSummary() } }
            .disabled(model.summaryTest.isTesting)
          SummaryTestView(state: model.summaryTest)
        }
        Text(
          "The key is kept in the Keychain and never shown again. A gateway may take an alias "
            + "such as haiku as the model."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Section("When") {
        Stepper(
          "\(settingLabel(.summaryMinAwayMinutes)): \(model.config.summary.minAwayMinutes)",
          value: Binding(
            get: { model.config.summary.minAwayMinutes },
            set: { value in Task { await model.setSummaryMinAwayMinutes(value) } }),
          in: 0...600, step: 5
        )
        .help(settingCommandHint(.summaryMinAwayMinutes))
        Stepper(
          "\(settingLabel(.summaryMinMessages)): \(model.config.summary.minMessages)",
          value: Binding(
            get: { model.config.summary.minMessages },
            set: { value in Task { await model.setSummaryMinMessages(value) } }),
          in: 1...100
        )
        .help(settingCommandHint(.summaryMinMessages))
      }
    }
    .formStyle(.grouped)
  }
}

private struct SummaryTestView: View {
  let state: SummaryTestState

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case .testing:
      ProgressView().controlSize(.small)
    case .succeeded(let reply):
      Label(reply, systemImage: "checkmark.circle.fill").foregroundStyle(.green).lineLimit(2)
    case .failed(let reason):
      Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(3)
    }
  }
}
