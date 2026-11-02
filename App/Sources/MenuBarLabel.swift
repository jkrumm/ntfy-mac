import NtfyAppLogic
import SwiftUI

/// The menu bar item: a symbol chosen by the model, and the unread count next to it. The label
/// supports only `Image` and `Text`. It also hands `openWindow` to the coordinator and answers
/// window requests, because this view exists from launch on, unlike the popover content.
struct MenuBarLabel: View {
  let model: AppModel
  let windows: WindowRouter
  let coordinator: WindowCoordinator
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Image(systemName: model.menuBarIcon.symbolName)
      .task {
        coordinator.install(openWindow)
        coordinator.fulfil(windows)
      }
      .onChange(of: windows.request) { coordinator.fulfil(windows) }
    if let badge = model.badgeText {
      Text(badge)
    }
  }
}
