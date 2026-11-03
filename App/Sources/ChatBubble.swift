import AppKit
import NtfyAppLogic
import NtfyCore
import SwiftUI

/// One message as a bubble: own messages right in the accent colour, received ones left. A
/// high or urgent priority adds a tint and a coloured bar on the leading edge.
struct ChatBubble: View {
  private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

  let model: HistoryModel
  let message: ChatMessage
  /// The "All" thread says which topic each message belongs to.
  let showsTopic: Bool
  @Binding var quickLook: URL?
  let delete: (MessageKey) -> Void
  let report: (String) -> Void

  private var detail: MessageDetail { message.detail }
  private var isOwn: Bool { message.isOwn }
  private var ink: Color { isOwn ? .white : .primary }
  private var subdued: Color { isOwn ? .white.opacity(0.75) : .secondary }

  var body: some View {
    HStack(spacing: 0) {
      if isOwn { Spacer(minLength: 72) }
      bubble
        .frame(maxWidth: 540, alignment: isOwn ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
      if !isOwn { Spacer(minLength: 72) }
    }
    .frame(maxWidth: .infinity)
    .onAppear { model.messageAppeared(message.key) }
    .onDisappear { model.messageDisappeared(message.key) }
  }

  private var bubble: some View {
    VStack(alignment: .leading, spacing: 8) {
      if showsTopic {
        Text(verbatim: detail.key.topic)
          .font(.caption.weight(.semibold))
          .foregroundStyle(isOwn ? Color.white.opacity(0.85) : Color.accentColor)
      }
      if detail.hasTitle {
        Text(verbatim: detail.title)
          .font(.body.weight(.bold))
          .textSelection(.enabled)
      }
      bodyText
      if !detail.tagLabels.isEmpty { tags }
      if let url = detail.clickURL { link(url) }
      if let file = detail.attachment {
        AttachmentPreview(
          model: model, key: detail.key, file: file, quickLook: $quickLook, report: report)
      }
      if !detail.actions.isEmpty { senderActions }
      footer
    }
    .foregroundStyle(ink)
    .tint(isOwn ? .white : nil)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      Self.shape.fill(isOwn ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
    )
    .background(Self.shape.fill(priorityTint.opacity(0.14)))
    .overlay(alignment: .leading) {
      if priorityTint != .clear {
        Rectangle().fill(priorityTint).frame(width: 4)
      }
    }
    .clipShape(Self.shape)
    .overlay(Self.shape.strokeBorder(.separator.opacity(isOwn ? 0 : 0.6)))
    .contextMenu { menu }
  }

  /// Only high and urgent get a tint; the rest stay plain.
  private var priorityTint: Color {
    detail.priority >= .high ? detail.priority.tint : .clear
  }

  @ViewBuilder private var bodyText: some View {
    if detail.body.isEmpty {
      EmptyView()
    } else if detail.isMarkdown {
      Text(MessageBodyRenderer.render(detail.body)).textSelection(.enabled)
    } else {
      Text(verbatim: detail.body).textSelection(.enabled)
    }
  }

  private var tags: some View {
    ChatFlowLayout(spacing: 4) {
      ForEach(Array(detail.tagLabels.enumerated()), id: \.offset) { _, label in
        Text(verbatim: label)
          .font(.caption)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(ink.opacity(0.12), in: Capsule())
      }
    }
  }

  private func link(_ url: URL) -> some View {
    Button {
      Task { _ = await model.open(url) }
    } label: {
      Label(url.absoluteString, systemImage: "link").lineLimit(1).truncationMode(.middle)
    }
    .buttonStyle(.plain)
    .font(.callout)
    .underline()
    .help("Open \(url.absoluteString)")
  }

  /// `view` actions open their link; the others run from the notification only.
  private var senderActions: some View {
    ChatFlowLayout(spacing: 6) {
      ForEach(detail.actions) { action in
        Button {
          if let url = action.url { Task { _ = await model.open(url) } }
        } label: {
          Text(verbatim: action.label)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(action.kind != "view" || action.url == nil)
        .help(
          action.kind == "view" && action.url != nil
            ? "Open the link" : "This action runs from the notification.")
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 6) {
      if !isOwn && !detail.isRead {
        Circle().fill(Color.accentColor).frame(width: 7, height: 7)
          .accessibilityLabel("Unread")
      }
      if model.canAcknowledge(detail) {
        Button("Acknowledge") { Task { await model.acknowledge(message.key) } }
          .buttonStyle(.bordered)
          .controlSize(.mini)
      }
      Spacer(minLength: 8)
      if detail.isAcknowledged {
        Image(systemName: "checkmark.circle.fill")
          .help("Acknowledged")
          .accessibilityLabel("Acknowledged")
      }
      if let remindAt = detail.remindAt {
        Image(systemName: "bell")
          .help("Reminder \(remindAt.formatted(date: .abbreviated, time: .shortened))")
          .accessibilityLabel("Reminder set")
      }
      if detail.priority != .default && !isOwn {
        PriorityMarker(priority: detail.priority)
      }
      Text(detail.time.formatted(date: .omitted, time: .shortened))
        .monospacedDigit()
    }
    .font(.caption)
    .foregroundStyle(subdued)
  }

  /// Right-click on a bubble: copy what it says, open its link, then what can be done to it.
  @ViewBuilder private var menu: some View {
    Button("Copy Text") { copy(detail.body.isEmpty ? detail.title : detail.body) }
    if detail.hasTitle {
      Button("Copy Title") { copy(detail.title) }
    }
    if let url = detail.clickURL {
      Button("Open Link") { Task { _ = await model.open(url) } }
    }
    Divider()
    if model.canAcknowledge(detail) {
      Button("Acknowledge") { Task { await model.acknowledge(message.key) } }
    }
    Button(detail.isRead ? "Mark Unread" : "Mark Read") {
      Task {
        if detail.isRead {
          await model.markUnread(message.key)
        } else {
          await model.markRead(message.key)
        }
      }
    }
    Menu("Remind Me") {
      ForEach(RemindChoice.allCases, id: \.self) { choice in
        Button(choice.title) { Task { await model.remind(choice, message.key) } }
      }
    }
    Divider()
    Button("Delete…", role: .destructive) { delete(message.key) }
  }

  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
