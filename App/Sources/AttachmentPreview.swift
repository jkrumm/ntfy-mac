import AppKit
import ImageIO
import NtfyAppLogic
import SwiftUI

/// The attachment of the shown message: facts, a button to fetch it, then a preview and the
/// file actions once it is local.
struct AttachmentPreview: View {
  let model: HistoryModel
  let file: MessageDetail.Attachment
  @Binding var quickLook: URL?
  let report: (String) -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
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
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(4)
    } label: {
      Text("Attachment")
    }
  }

  @ViewBuilder private var content: some View {
    switch model.attachment {
    case .idle:
      Button {
        model.loadAttachment()
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
        Button("Cancel") { model.cancelAttachment() }
      }
    case .failed(let reason):
      Text(verbatim: reason).foregroundStyle(.red)
      Button("Try Again") { model.loadAttachment() }
    case .ready(let url):
      ready(url)
    }
  }

  private func ready(_ url: URL) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if file.isImage {
        LocalImage(url: url)
      } else {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
          .resizable()
          .frame(width: 64, height: 64)
          .accessibilityHidden(true)
      }
      HStack {
        Button {
          quickLook = url
        } label: {
          Label("Quick Look", systemImage: "eye")
        }
        Button {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
          Label("Reveal in Finder", systemImage: "folder")
        }
        Button {
          Task {
            do { try await HistoryFiles.saveCopy(of: url, named: file.name) } catch {
              report("The attachment could not be saved: \(error.localizedDescription)")
            }
          }
        } label: {
          Label("Save As…", systemImage: "square.and.arrow.down")
        }
      }
    }
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
          .frame(maxHeight: 360)
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
