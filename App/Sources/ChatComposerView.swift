import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The bar under the thread: priority, a growing text field and send. Return sends, Shift-Return
/// (or Option-Return) starts a new line. On the "All" entry it only explains itself.
struct ChatComposerView: View {
  private static let priorities: [Priority] = [.min, .low, .default, .high, .max]

  @Bindable var model: HistoryModel
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if case .failed(let reason) = model.composerState {
        Label {
          Text(verbatim: reason).textSelection(.enabled)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(.red)
      }
      if let explanation = model.composerAvailability.explanation {
        Text(verbatim: explanation)
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 6)
      } else {
        HStack(alignment: .bottom, spacing: 8) {
          priorityMenu
          field
          sendButton
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.bar)
    .task(id: model.selectedTopic) { focused = model.selectedTopic != nil }
  }

  private var field: some View {
    TextField(prompt, text: $model.draft, axis: .vertical)
      .textFieldStyle(.plain)
      .lineLimit(1...6)
      .focused($focused)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(
        Color(nsColor: .textBackgroundColor),
        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.separator)
      )
      .onKeyPress(.return, phases: .down) { press in
        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
          model.draft += "\n"
        } else {
          Task { await model.send() }
        }
        return .handled
      }
  }

  private var prompt: String {
    if case .ready(let topic) = model.composerAvailability { "Message \(topic)" } else { "Message" }
  }

  private var priorityMenu: some View {
    Menu {
      Picker("Priority", selection: $model.composerPriority) {
        ForEach(Self.priorities, id: \.self) { priority in
          Label(priority.name, systemImage: priority.symbol ?? "minus").tag(priority)
        }
      }
      .pickerStyle(.inline)
    } label: {
      Image(systemName: model.composerPriority.symbol ?? "flag")
        .foregroundStyle(
          model.composerPriority == .default ? Color.secondary : model.composerPriority.tint
        )
        .frame(width: 22, height: 28)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Priority: \(model.composerPriority.name)")
    .accessibilityLabel("Priority, \(model.composerPriority.name)")
  }

  private var sendButton: some View {
    Button {
      Task { await model.send() }
    } label: {
      if model.composerState == .sending {
        ProgressView().controlSize(.small).frame(width: 28, height: 28)
      } else {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 28))
          .foregroundStyle(model.canSend ? Color.accentColor : Color.secondary.opacity(0.5))
      }
    }
    .buttonStyle(.plain)
    .disabled(!model.canSend)
    .help("Send (Return)")
    .accessibilityLabel("Send")
  }
}
