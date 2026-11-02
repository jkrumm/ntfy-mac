import Foundation
import NtfyClient
import NtfyCore
import NtfyPlatform
import NtfyStore

/// What outlives a pipeline rebuild.
struct AppServices: Sendable {
  let config: FileConfigStore
  let center: LiveNotificationCenter
  let router: ResponseRouter
  let clock: SystemClock
}

/// Everything that runs for one resolved configuration: store, delivery, response handling and
/// the stream. Built once per configuration; a changed connection setting means `shutdown()`
/// and a new pipeline.
final class AppPipeline: Sendable {
  /// How often old history is pruned.
  static let retentionInterval: Duration = .seconds(60 * 60)

  private let services: AppServices
  private let store: SQLiteHistoryStore
  private let delivery: DeliveryService
  private let supervisor: StreamSupervisor
  private let retention: Task<Void, Never>

  /// Opens the store and starts everything. Throws only when the history cannot be opened.
  static func start(settings: Settings, services: AppServices) async throws(NtfyError)
    -> AppPipeline
  {
    let log = Log.logger(.delivery)
    let store = try SQLiteHistoryStore.open(
      at: StoreLocation.databaseURL(applicationSupport: applicationSupport()),
      server: settings.origin, clock: services.clock)
    let token = settings.token
    let poster = UserNotificationPoster(
      center: services.center,
      images: URLSessionImageFetcher(
        server: settings.url, token: { token }, allowInsecure: settings.allowInsecure),
      log: { log.info("\($0, privacy: .public)") })
    let delivery = DeliveryService(
      poster: poster, history: store, inbox: store, config: services.config,
      clock: services.clock, log: { log.info("\($0, privacy: .public)") })

    await delivery.start()
    await poster.restoreDeliveredCategories(inbox: store, config: services.config.load())
    await delivery.reconcile()
    await services.router.use(
      responseHandler(store: store, delivery: delivery, services: services))

    let supervisor = StreamSupervisor(
      ports: ports(settings: settings, store: store, delivery: delivery, services: services),
      options: options(settings: settings, delivery: delivery))
    await supervisor.start()
    return AppPipeline(
      services: services, store: store, delivery: delivery, supervisor: supervisor)
  }

  private init(
    services: AppServices, store: SQLiteHistoryStore, delivery: DeliveryService,
    supervisor: StreamSupervisor
  ) {
    self.services = services
    self.store = store
    self.delivery = delivery
    self.supervisor = supervisor
    retention = Task { [store, clock = services.clock] in
      await Self.pruneForever(store: store, clock: clock)
    }
  }

  /// Supervisor first, then the retention loop and delivery, and last the store.
  func shutdown() async {
    await supervisor.stop()
    retention.cancel()
    await retention.value
    await delivery.shutdown()
    await services.router.use(nil)
  }

  // MARK: Wiring

  private static func responseHandler(
    store: SQLiteHistoryStore, delivery: DeliveryService, services: AppServices
  ) -> ResponseHandler {
    let log = Log.logger(.delivery)
    return ResponseHandler(
      delivery: delivery, inbox: store, config: services.config, opener: WorkspaceLinkOpener(),
      presenter: ActivatingHistoryPresenter(), confirmer: AlertConfirmer(),
      runner: URLSessionHTTPActionRunner(), log: { log.info("\($0, privacy: .public)") })
  }

  private static func ports(
    settings: Settings, store: SQLiteHistoryStore, delivery: DeliveryService,
    services: AppServices
  ) -> StreamSupervisor.Ports {
    let log = Log.logger(.stream)
    let diagnostics: @Sendable (String) -> Void = { log.debug("\($0, privacy: .public)") }
    return StreamSupervisor.Ports(
      stream: URLSessionMessageStream(
        base: settings.url, token: settings.token, allowInsecure: settings.allowInsecure,
        diagnostics: diagnostics),
      poller: NtfyPoller(
        base: settings.url, token: settings.token, allowInsecure: settings.allowInsecure,
        diagnostics: diagnostics),
      topics: NtfyAccountClient(
        base: settings.url, token: settings.token, allowInsecure: settings.allowInsecure),
      cursor: FileCursorStore(), history: store, delivery: delivery,
      systemEvents: SystemEventMonitor(), clock: services.clock)
  }

  private static func options(settings: Settings, delivery: DeliveryService)
    -> StreamSupervisor.Options
  {
    let log = Log.logger(.stream)
    var options = StreamSupervisor.Options()
    options.selection = settings.topicSelection
    options.log = { log.info("\($0, privacy: .public)") }
    options.sink = delivery.eventSink()
    options.activity = {
      let activity = ProcessActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "ntfy stream")
      return { activity.end() }
    }
    return options
  }

  // MARK: Retention

  private static func pruneForever(store: SQLiteHistoryStore, clock: SystemClock) async {
    let log = Log.logger(.store)
    while !Task.isCancelled {
      do throws(NtfyError) {
        let dropped = try await store.prune(policy: RetentionPolicy(), now: clock.now())
        if dropped > 0 { log.info("pruned \(dropped, privacy: .public) history rows") }
      } catch {
        log.error("history not pruned: \(String(describing: error), privacy: .public)")
      }
      do { try await clock.sleep(for: retentionInterval) } catch { return }
    }
  }

  private static func applicationSupport() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support", directoryHint: .isDirectory)
  }
}
