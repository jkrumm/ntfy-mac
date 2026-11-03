import AppKit
import ImageIO
import NtfyAppLogic
import SwiftUI

/// The attachment of a message, in the detail pane: facts, a button to fetch it, then a
/// preview and the file actions once it is local. A click on the preview opens Quick Look.
struct AttachmentPreview: View {
  let model: HistoryModel
  let key: MessageKey
  let file: MessageDetail.Attachment
  @Binding var quickLook: URL?
  let report: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        VStack(alignment: .leading) {
          Text(verbatim: file.name).fontWeight(.medium)
          Text(verbatim: facts).font(.caption).foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: file.isImage ? "photo" : "paperclip")
      }
      content
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  @ViewBuilder private var content: some View {
    switch model.attachmentState(for: key) {
    case .idle:
      Button {
        model.loadAttachment(for: key)
      } label: {
        Label(file.isImage ? "Load Image" : "Download", systemImage: "arrow.down.circle")
      }
      .disabled(file.isExpired)
      if file.isExpired {
        Text("The server no longer has this attachment.").font(.caption).foregroundStyle(.secondary)
      }
    case .loading:
      HStack {
        ProgressView().controlSize(.small)
        Text("Loading…")
        Button("Cancel") { model.cancelAttachment(for: key) }
      }
    case .failed(let reason):
      Text(verbatim: reason).foregroundStyle(.red)
      Button("Try Again") { model.loadAttachment(for: key) }
    case .ready(let url):
      ready(url)
    }
  }

  private func ready(_ url: URL) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        quickLook = url
      } label: {
        if file.isImage {
          LocalImage(url: url)
        } else {
          Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
        }
      }
      .buttonStyle(.plain)
      .help("Quick Look")
      // Whole labels while they fit, else icons with the label as help: a label never truncates.
      ViewThatFits(in: .horizontal) {
        fileActions(url).fixedSize()
        fileActions(url).labelStyle(.iconOnly).fixedSize()
      }
    }
  }

  private func fileActions(_ url: URL) -> some View {
    HStack {
      Button {
        quickLook = url
      } label: {
        Label("Quick Look", systemImage: "eye")
      }
      .help("Quick Look")
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } label: {
        Label("Reveal in Finder", systemImage: "folder")
      }
      .help("Reveal in Finder")
      Button {
        Task {
          do { try await HistoryFiles.saveCopy(of: url, named: file.name) } catch {
            report("The attachment could not be saved: \(error.localizedDescription)")
          }
        }
      } label: {
        Label("Save As…", systemImage: "square.and.arrow.down")
      }
      .help("Save a copy")
    }
    .controlSize(.small)
  }

  private var facts: String {
    var parts: [String] = []
    if let size = file.size { parts.append(size.formatted(.byteCount(style: .file))) }
    if let type = file.mimeType { parts.append(type) }
    return parts.isEmpty ? "Unknown size" : parts.joined(separator: " · ")
  }
}

/// An image from a local file, decoded off the main actor and scaled to fit.
private struct LocalImage: View {
  let url: URL
  @State private var image: CGImage?
  @State private var failed = false

  var body: some View {
    Group {
      if let image {
        Image(nsImage: NSImage(cgImage: image, size: .zero))
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 280)
          .accessibilityLabel("Image preview")
      } else if failed {
        Label("This image cannot be previewed.", systemImage: "photo.badge.exclamationmark")
          .foregroundStyle(.secondary)
      } else {
        ProgressView().controlSize(.small)
      }
    }
    .task(id: url) {
      image = nil
      failed = false
      let decoded = await Task.detached { Self.decode(url) }.value
      image = decoded
      failed = decoded == nil
    }
  }

  /// Decodes fully (`ShouldCacheImmediately`) and caps the size, so drawing is cheap.
  private nonisolated static func decode(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: 2048,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }
}
