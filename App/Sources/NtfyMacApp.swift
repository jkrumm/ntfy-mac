import AppKit
import NtfyCore
import NtfyPlatform
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let router = ResponseRouter()
  private let responder: NotificationResponder
  private let controller: AppController

  override init() {
    let router = router
    responder = NotificationResponder { await router.handle($0) }
    controller = AppController(router: router)
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    // The center only keeps a weak reference, and it needs its delegate before the first
    // notification response is delivered.
    UNUserNotificationCenter.current().delegate = responder
    let controller = controller
    Task { await controller.start() }
  }

  /// A bounded graceful stop: the stream ends and delivery settles, but never for long.
  func applicationWillTerminate(_ notification: Notification) {
    let controller = controller
    let done = DispatchSemaphore(value: 0)
    Task.detached {
      await controller.stop()
      done.signal()
    }
    _ = done.wait(timeout: .now() + .seconds(3))
  }
}

@main
struct NtfyMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    Settings { EmptyView() }
  }
}
