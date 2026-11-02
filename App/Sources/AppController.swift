import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyIPC
import NtfyPlatform

/// Owns the running pipeline: resolves the configuration, builds and tears down the pipeline when
/// the connection settings change, and follows the config file. It decides nothing itself;
/// `PipelineReload` does. It is also where the UI gets the running pipeline from
/// (`PipelineSource`), and tells it each time one is built or torn down.
actor AppController: PipelineSource, MeetingSource {
  private enum Lifecycle { case new, starting, running, stopped }

  nonisolated let services: AppServices
  private let rebuildSignal = ChangeSignal()
  private let secrets = KeychainSecretStore()
  private let log = Log.logger(.delivery)
  private var lifecycle = Lifecycle.new
  private var currentSettings: Settings?
  private var pipeline: AppPipeline?
  private var watcher: Task<Void, Never>?
  private var permissionTask: Task<Void, Never>?
  private var ipc: IPCServer?

  init(router: ResponseRouter, windows: WindowRouter) {
    services = AppServices(
      config: FileConfigStore(),
      center: LiveNotificationCenter(log: { Log.logger(.delivery).info("\($0, privacy: .private)") }
      ),
      router: router, clock: SystemClock(), windows: windows,
      meeting: MeetingMonitor(
        source: SystemMeetingSignalSource(), clock: SystemClock(),
        log: { Log.logger(.meeting).info("\($0, privacy: .private)") }))
  }

  private var isActive: Bool { lifecycle == .starting || lifecycle == .running }

  /// Migrates the token, builds the first pipeline and starts following the config file. The
  /// authorization prompt runs on its own task: startup never waits for the user. A `stop()` that
  /// arrives while this is suspended wins: nothing is built after it, and a pipeline that was
  /// being built is shut down again.
  func start() async {
    guard lifecycle == .new else { return }
    lifecycle = .starting
    startIPC()
    // Created first, so an edit while the first pipeline is being built is not missed.
    let changes = ConfigWatcher().changes()
    await migrateToken()
    guard isActive else { return }
    await cleanLegacyInstall()
    guard isActive else { return }
    permissionTask = Task { await self.requestPermissionOnce() }
    await reload()
    guard lifecycle == .starting else { return }
    lifecycle = .running
    watcher = Task {
      for await _ in changes { await self.reload() }
    }
  }

  /// Stops following the config and tears the pipeline down. Idempotent.
  func stop() async {
    guard lifecycle != .stopped else { return }
    lifecycle = .stopped
    await ipc?.stop()
    ipc = nil
    await services.meeting.stop()
    permissionTask?.cancel()
    permissionTask = nil
    watcher?.cancel()
    await watcher?.value
    watcher = nil
    await teardown()
  }

  /// The running pipeline, nil only while one is being rebuilt (or the history cannot be
  /// opened). Without a configured server it is the local pipeline.
  func runningPipeline() -> AppPipeline? { pipeline }

  func current() async -> PipelineHandles? { pipeline?.handles }

  nonisolated func rebuilds() -> AsyncStream<Void> { rebuildSignal.stream() }

  nonisolated var meetingState: any MeetingStateProviding { services.meeting }

  // MARK: Socket

  /// The socket outlives pipeline rebuilds: its handler asks this controller for the pipeline
  /// each time. A socket that cannot be bound is logged; the stream still runs.
  private func startIPC() {
    let log = Log.logger(.ipc)
    let handler = IPCRequestHandler(
      pipeline: { await self.runningPipeline()?.handles }, config: services.config,
      permissions: UserNotificationPermissionProvider(center: services.center),
      clock: services.clock, loginItem: SMAppServiceLoginItem(), meeting: services.meeting,
      log: { log.error("\($0, privacy: .public)") })
    let server = IPCServer(
      path: SocketPath.default(applicationSupport: AppPipeline.applicationSupport()),
      log: { log.error("\($0, privacy: .public)") },
      handler: { await handler.handle($0) })
    do throws(IPCError) {
      try server.start()
      ipc = server
    } catch {
      log.error("socket not started: \(String(describing: error), privacy: .public)")
    }
  }

  // MARK: Reload

  private func reload() async {
    guard isActive else { return }
    await syncMeetingDetection()
    let outcome = await resolve()
    guard isActive else { return }
    if case .failed(let reason) = outcome {
      log.error("configuration not read, keeping what runs: \(reason, privacy: .public)")
    }
    switch PipelineReload.decide(current: currentSettings, outcome: outcome) {
    case .keep:
      if case .resolved(let settings) = outcome { currentSettings = settings }
    case .idle:
      await teardown()
      log.info("not configured; local pipeline only")
    case .rebuild:
      await teardown()
      if case .resolved(let settings) = outcome { await build(settings) }
    }
    // Nothing runs yet (first start, idle, or a build that failed): the local pipeline keeps
    // `notify` working and is retried on every reload.
    if pipeline == nil { await build(nil) }
  }

  /// Runs the meeting detection only while the mode asks for it, so a user who never turned it
  /// on has no listeners and no reads. Delivery is told, because turning the mode off (or the
  /// override) can end a hold with nothing else to wake it.
  private func syncMeetingDetection() async {
    if await services.config.load().meeting.mode == .pause {
      await services.meeting.start()
    } else {
      await services.meeting.stop()
    }
    await pipeline?.delivery.recheckHold()
  }

  /// Builds the pipeline for `settings`, or the local one for nil.
  private func build(_ settings: Settings?) async {
    guard isActive else { return }
    do throws(NtfyError) {
      let started = try await AppPipeline.start(settings: settings, services: services)
      guard isActive else {
        await started.shutdown()
        return
      }
      pipeline = started
      currentSettings = settings
      rebuildSignal.fire()
      log.info("pipeline started for \(settings?.origin ?? "local", privacy: .private)")
    } catch {
      log.error("pipeline not started: \(String(describing: error), privacy: .public)")
    }
  }

  private func teardown() async {
    let running = pipeline
    pipeline = nil
    currentSettings = nil
    rebuildSignal.fire()
    await running?.shutdown()
  }

  /// Anything that cannot be read or validated is `.failed`, never `.unconfigured`: a
  /// half-written file or a Keychain hiccup must not stop a healthy stream.
  private func resolve() async -> SettingsOutcome {
    let config: Config
    do throws(NtfyError) {
      config = try await services.config.loadChecked()
    } catch {
      return .failed("config file: \(error)")
    }
    let token: String?
    do throws(NtfyError) {
      token = try await secrets.token()
    } catch {
      return .failed("keychain: \(error)")
    }
    do {
      let resolution = try ConfigResolver.resolve(
        config: config, keychainToken: token,
        environment: ConfigEnvironment(ProcessInfo.processInfo.environment))
      guard case .configured(let settings) = resolution else { return .unconfigured }
      return .resolved(settings)
    } catch {
      return .failed(error.description)
    }
  }

  // MARK: Launch tasks

  private func migrateToken() async {
    do throws(NtfyError) {
      let outcome = try await ConfigTokenMigration(config: services.config, secrets: secrets).run()
      log.info("token migration: \(String(describing: outcome), privacy: .public)")
    } catch {
      log.error("token migration failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Removes what a 1.x install left behind (service, daemon, helper app, old binary and logs)
  /// before anything starts. The cheap check runs first; only when it finds something does the
  /// full cleanup run, which also scans Launch Services. Never throws.
  private func cleanLegacyInstall() async {
    let cleanup = LegacyInstallCleanup.live(
      home: FileManager.default.homeDirectoryForCurrentUser,
      runningExecutable: Bundle.main.executableURL)
    guard !(await cleanup.detect(scope: .quick)).found.isEmpty else { return }
    let report = await cleanup.run()
    log.info(
      "1.x cleanup: removed \(report.removed, privacy: .private), failed \(report.failed, privacy: .private)"
    )
    if !report.failed.isEmpty {
      log.error("1.x cleanup: \(report.failed.count) step(s) failed; run: ntfy-mac migrate")
    }
  }

  /// Asks for notification permission when the system has not been asked yet. The process is kept
  /// from exiting while the prompt is open.
  private func requestPermissionOnce() async {
    let provider = UserNotificationPermissionProvider(center: services.center)
    var permission = await provider.current()
    if permission.authorization == .notDetermined {
      let guardrail = ProcessActivity(
        options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
        reason: "notification authorization prompt")
      permission = await provider.requestAuthorization()
      guardrail.end()
    }
    let problems = permission.problems.map(\.code).joined(separator: ",")
    log.info("notification permission problems: [\(problems, privacy: .public)]")
  }
}
