import AppKit
import NtfyAppLogic
import NtfyClient
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
  /// The History window's model; the window starts and stops it.
  let historyModel: HistoryModel
  /// The Settings window's model; the window starts and stops it.
  let settingsModel: SettingsModel
  let onboardingModel: OnboardingModel
  let coordinator: WindowCoordinator
  let updater: SparkleUpdater

  override init() {
    let router = router
    let windows = windows
    responder = NotificationResponder(
      handler: { await router.handle($0) }, onSummary: { await windows.showHistory() })
    let updater = SparkleUpdater(
      channel: InstallChannel.detect(executablePath: Bundle.main.executablePath ?? ""),
      disabled: ProcessInfo.processInfo.environment["NTFY_MAC_NO_SELF_UPDATE"] == "1",
      signing: BundleSigningInspector(bundle: Bundle.main.bundleURL),
      pins: FileTeamPinStore(
        url: FileTeamPinStore.defaultURL(applicationSupport: AppPipeline.applicationSupport())),
      log: { Log.logger(.interface).info("\($0, privacy: .public)") })
    self.updater = updater
    let controller = AppController(router: router, windows: windows, updates: updater)
    self.controller = controller
    let services = controller.services
    model = AppModel(
      source: controller, meeting: services.meeting, config: services.config,
      permissions: UserNotificationPermissionProvider(center: services.center),
      clock: services.clock, configChanges: { ConfigWatcher().changes() },
      log: { Log.logger(.interface).info("\($0, privacy: .private)") })
    historyModel = HistoryModel(
      source: controller, opener: WorkspaceLinkOpener(), clock: services.clock,
      config: services.config,
      log: { Log.logger(.interface).info("\($0, privacy: .private)") })
    let configChanges: @Sendable () -> AsyncStream<Void> = { ConfigWatcher().changes() }
    let secrets = KeychainSecretStore()
    let tester = NtfyServerTester()
    let loginItem = SMAppServiceLoginItem()
    func permissionFlow() -> NotificationPermissionFlow {
      NotificationPermissionFlow(
        permissions: UserNotificationPermissionProvider(center: services.center),
        opener: WorkspaceLinkOpener(), quitGuard: ProcessQuitGuard(), source: controller,
        clock: services.clock)
    }
    settingsModel = SettingsModel(
      SettingsModel.Dependencies(
        config: services.config, secrets: secrets, tester: tester,
        topicSource: ConfiguredTopicSource(config: services.config, secrets: secrets),
        source: controller, loginItem: loginItem, sounds: SystemSoundList(),
        preview: NSSoundPreview(), configChanges: configChanges),
      app: model, permission: permissionFlow(), windows: windows,
      log: { Log.logger(.interface).info("\($0, privacy: .private)") })
    onboardingModel = OnboardingModel(
      config: services.config, secrets: secrets, tester: tester, loginItem: loginItem,
      permission: permissionFlow())
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
    updater.start()
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

  /// A second `open` of the running app, or a Dock icon click, arrives as a reopen: front the
  /// visible window, or open History when there is none.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    windows.reopen(hasVisibleWindows: flag)
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

#if !SNAPSHOT_HARNESS
  @main
#endif
struct NtfyMacApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarContent(
        model: delegate.model, windows: delegate.windows, coordinator: delegate.coordinator,
        updates: delegate.updater.menu)
    } label: {
      MenuBarLabel(
        model: delegate.model, windows: delegate.windows, coordinator: delegate.coordinator)
    }
    .menuBarExtraStyle(.window)

    Window(AppWindow.history.title, id: AppWindow.history.rawValue) {
      HistoryWindow(model: delegate.historyModel, windows: delegate.windows)
    }
    .defaultSize(AppWindow.history.defaultSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)

    Window(AppWindow.settings.title, id: AppWindow.settings.rawValue) {
      SettingsWindow(model: delegate.settingsModel)
    }
    .defaultSize(AppWindow.settings.defaultSize)
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { delegate.coordinator.show(.settings) }
          .keyboardShortcut(",")
      }
    }

    Window(AppWindow.onboarding.title, id: AppWindow.onboarding.rawValue) {
      OnboardingWindow(model: delegate.onboardingModel)
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
  }
}
