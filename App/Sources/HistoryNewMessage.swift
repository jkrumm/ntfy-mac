import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The "New message…" popover: topic, priority and text. Command-Return sends; the popover
/// closes once the message is on its way, and a failed send keeps the text and says why.
struct HistoryNewMessage: View {
  private static let priorities: [Priority] = [.min, .low, .default, .high, .max]

  @Bindable var model: HistoryModel
  let dismiss: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("New message").font(.headline)
      if let explanation = model.composerAvailability.explanation {
        Text(verbatim: explanation).foregroundStyle(.secondary)
      } else {
        form
      }
      if case .failed(let reason) = model.composerState {
        Label {
          Text(verbatim: reason).textSelection(.enabled)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
        Button {
          Task {
            await model.send()
            if model.composerState == .idle && model.draft.isEmpty { dismiss() }
          }
        } label: {
          if model.composerState == .sending {
            ProgressView().controlSize(.small)
          } else {
            Text("Send")
          }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .buttonStyle(.borderedProminent)
        .disabled(!model.canSend)
        .help("Send (⌘Return)")
      }
    }
    .padding(14)
    .frame(width: 340)
    .onAppear { focused = true }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Picker("Topic", selection: topic) {
          ForEach(model.composerTopics, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        Picker("Priority", selection: $model.composerPriority) {
          ForEach(Self.priorities, id: \.self) { Text($0.name).tag($0) }
        }
        .fixedSize()
      }
      TextField("Message", text: $model.draft, axis: .vertical)
        .lineLimit(3...8)
        .textFieldStyle(.roundedBorder)
        .focused($focused)
    }
  }

  private var topic: Binding<String> {
    Binding(
      get: {
        if case .ready(let topic) = model.composerAvailability { topic } else { "" }
      },
      set: { model.composerTopic = $0 })
  }
}
