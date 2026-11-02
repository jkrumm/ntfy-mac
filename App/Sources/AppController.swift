import Foundation
import NtfyCore
import NtfyIPC
import NtfyPlatform

/// Owns the running pipeline: resolves the configuration, builds and tears down the pipeline when
/// the connection settings change, and follows the config file. It decides nothing itself;
/// `PipelineReload` does.
actor AppController {
  private enum Lifecycle { case new, starting, running, stopped }

  private let services: AppServices
  private let secrets = KeychainSecretStore()
  private let log = Log.logger(.delivery)
  private var lifecycle = Lifecycle.new
  private var current: Settings?
  private var pipeline: AppPipeline?
  private var watcher: Task<Void, Never>?
  private var permissionTask: Task<Void, Never>?
  private var ipc: IPCServer?

  init(router: ResponseRouter) {
    services = AppServices(
      config: FileConfigStore(),
      center: LiveNotificationCenter(log: { Log.logger(.delivery).info("\($0, privacy: .private)") }
      ),
      router: router, clock: SystemClock())
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
    permissionTask?.cancel()
    permissionTask = nil
    watcher?.cancel()
    await watcher?.value
    watcher = nil
    await teardown()
  }

  /// The running pipeline, nil while none is built (unconfigured, or being rebuilt).
  func runningPipeline() -> AppPipeline? { pipeline }

  // MARK: Socket

  /// The socket outlives pipeline rebuilds: its handler asks this controller for the pipeline
  /// each time. A socket that cannot be bound is logged; the stream still runs.
  private func startIPC() {
    let handler = AppIPCHandler(
      controller: self, config: services.config,
      permissions: UserNotificationPermissionProvider(center: services.center),
      clock: services.clock)
    let server = IPCServer(
      path: SocketPath.default(applicationSupport: AppPipeline.applicationSupport())
    ) { await handler.handle($0) }
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
    let outcome = await resolve()
    guard isActive else { return }
    if case .failed(let reason) = outcome {
      log.error("configuration not read, keeping what runs: \(reason, privacy: .public)")
    }
    switch PipelineReload.decide(current: current, outcome: outcome) {
    case .keep:
      if case .resolved(let settings) = outcome { current = settings }
    case .idle:
      await teardown()
      log.info("not configured; idle")
    case .rebuild:
      await teardown()
      if case .resolved(let settings) = outcome { await build(settings) }
    }
  }

  private func build(_ settings: Settings) async {
    guard isActive else { return }
    do throws(NtfyError) {
      let started = try await AppPipeline.start(settings: settings, services: services)
      guard isActive else {
        await started.shutdown()
        return
      }
      pipeline = started
      current = settings
      log.info("pipeline started for \(settings.origin, privacy: .private)")
    } catch {
      log.error("pipeline not started: \(String(describing: error), privacy: .public)")
    }
  }

  private func teardown() async {
    let running = pipeline
    pipeline = nil
    current = nil
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
