import AppKit
import SwiftUI

/// The row look of the menu bar popover, in one place: a full-width hit target that fills with the
/// system selection colour while the pointer is over it. The fill is a background only, so hovering
/// never moves the layout, and the keyboard focus ring of the underlying control is left alone.
struct MenuHover: ViewModifier {
  var pressed = false
  /// Names the row for the UI snapshots, which draw one row as hovered.
  var rowID: String?
  @State private var hovering = false
  @Environment(\.isEnabled) private var isEnabled
  #if SNAPSHOT_HARNESS
    @Environment(\.snapshotHoverID) private var snapshotHoverID
  #endif

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .background(RoundedRectangle(cornerRadius: 6).fill(fill))
      .onHover { hovering = $0 }
  }

  private var isHovered: Bool {
    #if SNAPSHOT_HARNESS
      if let rowID, rowID == snapshotHoverID { return true }
    #endif
    return hovering
  }

  private var fill: Color {
    guard isEnabled else { return .clear }
    let selection = Color(nsColor: .selectedContentBackgroundColor)
    if pressed { return selection.opacity(0.4) }
    return isHovered ? selection.opacity(0.25) : .clear
  }
}

extension View {
  /// Hover highlight for a row that is not a `Button` (it holds nested controls of its own).
  func menuHover(id: String? = nil) -> some View { modifier(MenuHover(rowID: id)) }
}

/// Button style for every actionable popover row. `compact` is for controls that sit inside a
/// status line rather than in the action list.
struct MenuRowStyle: ButtonStyle {
  var compact = false
  var rowID: String?

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 6)
      .padding(.vertical, compact ? 2 : 4)
      .modifier(MenuHover(pressed: configuration.isPressed, rowID: rowID))
  }
}

extension ButtonStyle where Self == MenuRowStyle {
  static var menuRow: MenuRowStyle { MenuRowStyle() }
  static var menuRowCompact: MenuRowStyle { MenuRowStyle(compact: true) }
}

/// Leading symbol, title, optional trailing accessory: the layout shared by all action rows.
struct MenuRowLabel<Trailing: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .frame(width: 16)
        .foregroundStyle(.secondary)
      Text(title)
      Spacer(minLength: 8)
      trailing
    }
  }
}

/// A plain action row: `MenuRow("Settings…", systemImage: "gearshape") { … }`.
struct MenuRow<Trailing: View>: View {
  let title: String
  let systemImage: String
  let action: () -> Void
  @ViewBuilder var trailing: Trailing

  init(
    _ title: String, systemImage: String, action: @escaping () -> Void,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
    self.trailing = trailing()
  }

  var body: some View {
    Button(action: action) {
      MenuRowLabel(title: title, systemImage: systemImage) { trailing }
    }
    .buttonStyle(MenuRowStyle(rowID: title))
  }
}

extension MenuRow where Trailing == EmptyView {
  init(_ title: String, systemImage: String, action: @escaping () -> Void) {
    self.init(title, systemImage: systemImage, action: action) { EmptyView() }
  }
}
