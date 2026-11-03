#if SNAPSHOT_HARNESS
  import AppKit
  import NtfyAppLogic
  import SwiftUI

  /// A window that stays where it is put: AppKit would pull a window that is entirely off screen
  /// back onto one.
  private final class OffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
      frameRect
    }
  }

  /// Draws a SwiftUI view in a real, never shown NSWindow far off screen and reads it back as a
  /// 2x PNG. A window (not `ImageRenderer`) because only AppKit draws the controls: Picker, List,
  /// Toggle and TextField. No Screen Recording permission is involved: the app reads its own views.
  @MainActor
  struct SnapshotRenderer {
    static let scale: CGFloat = 2

    let window: NSWindow
    let isPopover: Bool
    /// The size of the area below the title bar, which is what a SwiftUI frame sizes.
    private let contentSize: NSSize

    /// - Parameter height: nil sizes the window to its content, as the popover is.
    init(
      content: AnyView, width: Int, height: Int?, isPopover: Bool, appearance: SnapshotAppearance
    ) {
      self.isPopover = isPopover
      let host = NSHostingController(rootView: content)
      host.sizingOptions = []
      let style: NSWindow.StyleMask =
        isPopover ? [.borderless] : [.titled, .closable, .miniaturizable, .resizable]
      var contentHeight = CGFloat(height ?? 0)
      if height == nil {
        let fitting = NSHostingView(rootView: content)
        fitting.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: 10)
        contentHeight = ceil(fitting.fittingSize.height)
      }
      let rect = NSRect(x: -30000, y: -30000, width: CGFloat(width), height: contentHeight)
      window = OffscreenWindow(
        contentRect: rect, styleMask: style, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
      window.contentViewController = host
      window.setContentSize(NSSize(width: CGFloat(width), height: contentHeight))
      window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
      contentSize = NSSize(width: CGFloat(width), height: contentHeight)
      if isPopover {
        window.isOpaque = false
        window.backgroundColor = .clear
      }
    }

    /// The view that is drawn: for a window the frame view, which includes the title bar and the
    /// toolbar.
    private var captured: NSView {
      guard !isPopover, let frame = window.contentView?.superview else {
        return window.contentView ?? NSView()
      }
      return frame
    }

    /// Lets SwiftUI lay out and run `.task`/`onAppear` work.
    func settle(_ milliseconds: Int = 500) async {
      window.orderFrontRegardless()
      try? await Task.sleep(for: .milliseconds(milliseconds))
      fitContentLayout()
      window.contentView?.layoutSubtreeIfNeeded()
      captured.displayIfNeeded()
    }

    /// The PNG and its height in points.
    func png() -> (data: Data, height: Int)? {
      let view = captured
      view.layoutSubtreeIfNeeded()
      let bounds = view.bounds
      guard bounds.width > 0, bounds.height > 0,
        let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * Self.scale),
          pixelsHigh: Int(bounds.height * Self.scale), bitsPerSample: 8, samplesPerPixel: 4,
          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
          bitsPerPixel: 0)
      else { return nil }
      rep.size = bounds.size
      draw(view, into: rep)
      guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
      return (data, Int(bounds.height.rounded()))
    }

    /// The toolbar makes the title bar taller after the window was sized, which would squeeze
    /// the content below its minimum size: grow the window until the content area is as asked.
    private func fitContentLayout() {
      guard !isPopover else { return }
      let missing = contentSize.height - window.contentLayoutRect.height
      guard abs(missing) > 0.5 else { return }
      var frame = window.frame
      frame.size.height += missing
      window.setFrame(frame, display: true)
    }

    /// Every view below `root` whose class name contains `name`, outermost first.
    private func find(_ name: String, in root: NSView) -> [NSView] {
      let own = String(describing: type(of: root)).contains(name) ? [root] : []
      return own + root.subviews.flatMap { find(name, in: $0) }
    }

    /// `cacheDisplay` paints every glass view (the sidebar panel, toolbar buttons) as an opaque
    /// white shape over its content, and the sidebar's backdrop black. So the glass is hidden while
    /// the window is drawn, and the sidebar is drawn on its own and laid over an approximation of
    /// its panel in the window's appearance.
    private func draw(_ frame: NSView, into rep: NSBitmapImageRep) {
      let bounds = frame.bounds
      let glass = isPopover ? [] : find("GlassEffectView", in: frame)
      let backdrops = isPopover ? [] : find("BlurryAlleywayView", in: frame)
      let sidebar = find("SidebarStyleContext", in: frame).first
      let sidebarImage = sidebar.flatMap { bitmap(of: $0) }
      if window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        sidebarImage.map(Self.lightenVibrantText)
      }
      let sidebarRect = sidebar.map { $0.convert($0.bounds, to: frame) }
      let panelRects = glass.filter { String(describing: type(of: $0)).contains("Container") }
        .map { $0.convert($0.bounds, to: frame) }
      let alleyRects = backdrops.map { $0.convert($0.bounds, to: frame) }
      for view in glass + backdrops { view.isHidden = true }
      frame.cacheDisplay(in: bounds, to: rep)
      for view in glass + backdrops { view.isHidden = false }
      guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
      NSGraphicsContext.saveGraphicsState()
      defer { NSGraphicsContext.restoreGraphicsState() }
      NSGraphicsContext.current = context
      window.effectiveAppearance.performAsCurrentDrawingAppearance {
        NSColor.windowBackgroundColor.setFill()
        for rect in alleyRects { rect.fill() }
        NSColor.controlBackgroundColor.setFill()
        for rect in panelRects { NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill() }
        if let image = sidebarImage?.cgImage, let sidebarRect {
          context.cgContext.draw(image, in: sidebarRect)
        }
      }
    }

    /// The sidebar's labels are black masks that vibrancy turns light on glass; without the glass
    /// they would stay black on a dark panel. Dark pixels become white, with their alpha.
    private static func lightenVibrantText(_ rep: NSBitmapImageRep) {
      guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return }
      for row in 0..<rep.pixelsHigh {
        for column in 0..<rep.pixelsWide {
          let pixel = data + row * rep.bytesPerRow + column * 4
          guard pixel[3] > 0, pixel[0] < 40, pixel[1] < 40, pixel[2] < 40 else { continue }
          pixel[0] = pixel[3]
          pixel[1] = pixel[3]
          pixel[2] = pixel[3]
        }
      }
    }

    private func bitmap(of view: NSView) -> NSBitmapImageRep? {
      let bounds = view.bounds
      guard
        let rep = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * Self.scale),
          pixelsHigh: Int(bounds.height * Self.scale), bitsPerSample: 8, samplesPerPixel: 4,
          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
          bitsPerPixel: 0)
      else { return nil }
      rep.size = bounds.size
      window.effectiveAppearance.performAsCurrentDrawingAppearance {
        view.cacheDisplay(in: bounds, to: rep)
      }
      return rep
    }

    func close() {
      window.contentViewController = nil
      window.close()
    }
  }
#endif
