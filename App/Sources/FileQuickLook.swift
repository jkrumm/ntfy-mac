import QuickLook
import SwiftUI

extension View {
  /// Quick Look for a local file while `url` is set. The one place that depends on SwiftUI's
  /// `quickLookPreview`; swap it for a `QLPreviewPanel` bridge here if that modifier misbehaves.
  func fileQuickLook(_ url: Binding<URL?>) -> some View {
    quickLookPreview(url)
  }
}
