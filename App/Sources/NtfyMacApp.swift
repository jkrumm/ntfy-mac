import AppKit
import NtfyAppLogic
import NtfyCore
import NtfyPlatform
import SwiftUI
import UserNotifications

/// The composition root of the UI side: builds the model layer over the controller and hands it
/// to the scenes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let router = ResponseRouter { Log.logger(.delivery).info("\($0, privacy: .public)") }
  private let responder: NotificationResponder
  private let controller: AppController
  private let onboarding = OnboardingState(defaults: .standard)
  let windows = WindowRouter()
  let model: AppModel
  let coordinator: WindowCoordinator

  override init() {
    let router = router
    let windows = windows
    responder = NotificationResponder(
      handler: { await router.handle($0) }, onSummary: { await windows.showHistory() })
    let controller = AppController(router: router, windows: windows)
    self.controller = controller
    let services = controller.services
    model = AppModel(
      source: controller, config: services.config,
      permissions: UserNotificationPermissionProvider(center: services.center),
      clock: services.clock, configChanges: { ConfigWatcher().changes() },
      log: { Log.logger(.interface).info("\($0, privacy: .private)") })
    let onboarding = onboarding
    coordinator = WindowCoordinator { window in
      if window == .onboarding { onboarding.dismiss() }
    }
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    // The center only keeps a weak reference, and it needs its delegate before the first
    // notification response is delivered.
    UNUserNotificationCenter.current().delegate = responder
    model.start()
    let controller = controller
    Task {
      await controller.start()
      await welcomeIfFirstLaunch()
    }
  }

  /// A first launch without a server opens the welcome window, once.
  private func welcomeIfFirstLaunch() async {
    guard !onboarding.isDismissed, let pipeline = await controller.runningPipeline(),
      pipeline.supervisor == nil
    else { return }
    windows.showOnboarding()
  }

  /// A second `open` of the running app arrives as a reopen: show Settings.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    windows.showSettings()
    return false
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    Task { await model.refreshPermission() }
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
    MenuBarExtra {
      MenuBarContent(
        model: delegate.model, windows: delegate.windows, coordinator: delegate.coordinator)
    } label: {
      MenuBarLabel(
        model: delegate.model, windows: delegate.windows, coordinator: delegate.coordinator)
    }
    .menuBarExtraStyle(.window)

    Window(AppWindow.history.title, id: AppWindow.history.rawValue) {
      HistoryWindow(model: delegate.model, windows: delegate.windows)
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    Window(AppWindow.settings.title, id: AppWindow.settings.rawValue) {
      SettingsWindow(model: delegate.model)
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { delegate.coordinator.show(.settings) }
          .keyboardShortcut(",")
      }
    }

    Window(AppWindow.onboarding.title, id: AppWindow.onboarding.rawValue) {
      OnboardingWindow(model: delegate.model)
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
  }
}
