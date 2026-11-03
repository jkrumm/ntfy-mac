import NtfyAppLogic
import NtfyCore
import SwiftUI

struct SettingsTopicsSection: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      if model.topicRows.isEmpty {
        Section {
          Text("No topics yet. Add one below, or connect a server with subscriptions.")
            .foregroundStyle(.secondary)
        }
      }
      ForEach(model.topicRows) { row in
        TopicRowView(model: model, row: row)
      }
      Section {
        HStack {
          TextField("Topic name", text: $model.newTopicText)
            .labelsHidden()
            .autocorrectionDisabled()
            .onSubmit { Task { await model.addTypedTopic() } }
          Button("Add") { Task { await model.addTypedTopic() } }
            .disabled(model.newTopicText.isEmpty)
        }
        .help(settingCommandHint(.topicSubscribe))
      } header: {
        Text(settingLabel(.topicSubscribe))
      } footer: {
        Text(
          "Topics from your ntfy account are managed in the ntfy web app. "
            + "Muted topics are still stored in the history."
        )
      }
    }
    .formStyle(.grouped)
    .task { await model.reloadServerTopics() }
  }
}

/// One topic as its own group: the name and where it comes from on top, then the three
/// settings as labelled rows, so labels and controls line up the same way for every topic.
private struct TopicRowView: View {
  let model: SettingsModel
  let row: TopicRow
  @State private var emoji: String
  @FocusState private var emojiFocused: Bool

  init(model: SettingsModel, row: TopicRow) {
    self.model = model
    self.row = row
    _emoji = State(initialValue: row.settings.emoji ?? "")
  }

  var body: some View {
    Section {
      Toggle(
        "Mute",
        isOn: Binding(
          get: { row.settings.mute },
          set: { value in Task { await model.setMute(value, topic: row.name) } })
      )
      .help(settingCommandHint(.topicMute))
      LabeledContent("Minimum priority") {
        Picker("Minimum priority", selection: priority) {
          Text("Any").tag(0)
          ForEach(SettingsModel.priorities.reversed(), id: \.self) { value in
            Text(SettingsModel.priorityTitle(value)).tag(value)
          }
        }
        .labelsHidden()
        .fixedSize()
      }
      .help(settingCommandHint(.topicMinPriority))
      LabeledContent("Emoji") {
        TextField("Emoji", text: $emoji)
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .frame(width: 72)
          .focused($emojiFocused)
          .onSubmit(commitEmoji)
          .onChange(of: emojiFocused) { if !emojiFocused { commitEmoji() } }
      }
      .help(settingCommandHint(.topicEmoji))
    } header: {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: row.name)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(row.name)
        Text(origin).font(.caption).foregroundStyle(.secondary).fixedSize()
        Spacer(minLength: 8)
        if row.isLocal {
          Button("Remove", role: .destructive) { Task { await model.unsubscribe(row.name) } }
            .controlSize(.small)
            .help(settingCommandHint(.topicUnsubscribe))
        }
      }
      .textCase(nil)
    }
  }

  private var priority: Binding<Int> {
    Binding(
      get: { row.settings.minPriority ?? 0 },
      set: { value in
        Task { await model.setMinPriority(value == 0 ? nil : value, topic: row.name) }
      })
  }

  private var origin: String {
    switch row.origin {
    case .server: "on the server"
    case .local: "added here"
    case .seen: "seen in the history"
    }
  }

  private func commitEmoji() {
    guard emoji != (row.settings.emoji ?? "") else { return }
    Task { await model.setEmoji(emoji, topic: row.name) }
  }
}
