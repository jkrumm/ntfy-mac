import NtfyAppLogic
import SwiftUI

/// The selected message in full: header, actions, body, link, tags, attachment and the sender's
/// own actions.
struct HistoryDetail: View {
  let model: HistoryModel
  let detail: MessageDetail
  @Binding var quickLook: URL?
  @Binding var deleting: MessageKey?
  let report: (String) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        header
        HistoryDetailActions(model: model, detail: detail, deleting: $deleting)
        Divider()
        bodyText
        if let url = detail.clickURL { link(url) }
        if !detail.tagLabels.isEmpty { tags }
        if let file = detail.attachment {
          AttachmentPreview(
            model: model, key: detail.key, file: file, quickLook: $quickLook, report: report)
        }
        if !detail.actions.isEmpty { senderActions }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: detail.title)
        .font(.title3.bold())
        .textSelection(.enabled)
      HistoryFlowLayout(spacing: 10) {
        Label(detail.key.topic, systemImage: "number")
        Label {
          Text("\(detail.priority.name) priority")
        } icon: {
          Image(systemName: detail.priority.symbol ?? "minus")
        }
        .foregroundStyle(detail.priority.tint)
        Text(detail.time.formatted(date: .abbreviated, time: .standard))
        if detail.isAcknowledged {
          Label("Acknowledged", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
        if let remindAt = detail.remindAt {
          Label(
            "Reminder \(remindAt.formatted(date: .abbreviated, time: .shortened))",
            systemImage: "bell")
        }
      }
      .font(.callout)
      .foregroundStyle(.secondary)
    }
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

  private func link(_ url: URL) -> some View {
    Button {
      Task { _ = await model.open(url) }
    } label: {
      Label(url.absoluteString, systemImage: "link").lineLimit(1).truncationMode(.middle)
    }
    .buttonStyle(.link)
    .help("Open \(url.absoluteString)")
  }

  private var tags: some View {
    HistoryFlowLayout(spacing: 4) {
      ForEach(Array(detail.tagLabels.enumerated()), id: \.offset) { _, label in
        Text(verbatim: label)
          .font(.caption)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(.primary.opacity(0.08), in: Capsule())
      }
    }
  }

  /// `view` actions open their link; the others run from the notification only.
  private var senderActions: some View {
    HistoryFlowLayout(spacing: 6) {
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
}
