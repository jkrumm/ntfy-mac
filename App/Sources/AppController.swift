import Foundation
import NtfyCore
import NtfyPlatform

/// Owns the running pipeline: resolves the configuration, builds and tears down the pipeline when
/// the connection settings change, and follows the config file. It decides nothing itself;
/// `PipelineReload` does.
actor AppController {
  private let services: AppServices
  private let secrets = KeychainSecretStore()
  private let log = Log.logger(.delivery)
  private var current: Settings?
  private var pipeline: AppPipeline?
  private var watcher: Task<Void, Never>?

  init(router: ResponseRouter) {
    services = AppServices(
      config: FileConfigStore(),
      center: LiveNotificationCenter(log: { Log.logger(.delivery).info("\($0, privacy: .public)") }
      ),
      router: router, clock: SystemClock())
  }

  /// Migrates the token, builds the first pipeline and starts following the config file. The
  /// authorization prompt runs on its own task: startup never waits for the user.
  func start() async {
    guard watcher == nil else { return }
    await migrateToken()
    Task { await self.requestPermissionOnce() }
    await reload()
    let changes = ConfigWatcher().changes()
    watcher = Task {
      for await _ in changes { await self.reload() }
    }
  }

  /// Stops following the config and tears the pipeline down.
  func stop() async {
    watcher?.cancel()
    await watcher?.value
    watcher = nil
    await teardown()
  }

  // MARK: Reload

  private func reload() async {
    let resolved = await resolve()
    switch PipelineReload.decide(current: current, resolved: resolved) {
    case .keep:
      current = resolved
    case .idle:
      await teardown()
      log.info("not configured; idle")
    case .rebuild:
      await teardown()
      if let resolved { await build(resolved) }
    }
  }

  private func build(_ settings: Settings) async {
    do throws(NtfyError) {
      pipeline = try await AppPipeline.start(settings: settings, services: services)
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

  private func resolve() async -> Settings? {
    let config = await services.config.load()
    let token = try? await secrets.token()
    do {
      let resolution = try ConfigResolver.resolve(
        config: config, keychainToken: token,
        environment: ConfigEnvironment(ProcessInfo.processInfo.environment))
      guard case .configured(let settings) = resolution else { return nil }
      return settings
    } catch {
      log.error("configuration invalid: \(error.description, privacy: .public)")
      return nil
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
