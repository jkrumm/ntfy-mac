import NtfyAppLogic
import SwiftUI

/// The selected message in full.
struct HistoryDetail: View {
  let model: HistoryModel
  let detail: MessageDetail
  @Binding var confirmingDelete: Bool
  @Binding var quickLook: URL?
  let report: (String) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header
        HistoryDetailActions(model: model, detail: detail, confirmingDelete: $confirmingDelete)
        Divider()
        bodyText
        if let url = detail.clickURL {
          Button {
            Task { _ = await model.openClickURL() }
          } label: {
            Label(url.absoluteString, systemImage: "link").lineLimit(1).truncationMode(.middle)
          }
          .help("Open \(url.absoluteString)")
        }
        if !detail.actions.isEmpty { senderActions }
        if let file = detail.attachment {
          AttachmentPreview(model: model, file: file, quickLook: $quickLook, report: report)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: detail.title)
        .font(.title2.bold())
        .textSelection(.enabled)
      HStack(spacing: 8) {
        Label(detail.key.topic, systemImage: "number")
        if !detail.tagLabels.isEmpty { Text(verbatim: detail.tagLabels.joined(separator: " ")) }
        Label {
          Text("\(detail.priority.name) priority")
        } icon: {
          Image(systemName: detail.priority.symbol ?? "minus")
        }
        .foregroundStyle(detail.priority.tint)
        .labelStyle(.titleAndIcon)
      }
      .font(.callout)
      .foregroundStyle(.secondary)
      Text(detail.time.formatted(date: .complete, time: .standard))
        .font(.callout)
        .foregroundStyle(.secondary)
      if detail.isAcknowledged {
        Label("Acknowledged", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
      }
      if let remindAt = detail.remindAt {
        Label(
          "Reminder \(remindAt.formatted(date: .abbreviated, time: .shortened))",
          systemImage: "bell"
        )
        .foregroundStyle(.secondary)
      }
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

  /// The ntfy actions the sender attached. They run from the notification, not from here, so
  /// they are listed as text only.
  private var senderActions: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Sender actions (not available here)")
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(detail.actions) { action in
        Label(action.label, systemImage: "bolt")
          .foregroundStyle(.secondary)
      }
    }
  }
}
