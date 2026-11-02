import Foundation
import NtfyAppLogic
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
  let windows: WindowRouter
}

/// Everything that runs for one resolved configuration: store, delivery, response handling and
/// the stream. Built once per configuration; a changed connection setting means `shutdown()`
/// and a new pipeline. Without a configured server it is the local pipeline: the same store,
/// delivery and response handling under the `local` origin, and no stream, so `ntfy-mac notify`
/// and acknowledging its messages work before `setup`.
final class AppPipeline: Sendable {
  /// How often old history is pruned.
  static let retentionInterval: Duration = .seconds(60 * 60)
  /// The history key of the local pipeline; no real origin has this shape.
  static let localOrigin = "local"

  private let services: AppServices
  let store: SQLiteHistoryStore
  let delivery: DeliveryService
  /// Nil in the local pipeline.
  let supervisor: StreamSupervisor?
  let attachments: any AttachmentFetching
  private let retention: Task<Void, Never>

  /// Opens the store and starts everything; `settings` nil starts the local pipeline. Throws
  /// only when the history cannot be opened.
  static func start(settings: Settings?, services: AppServices) async throws(NtfyError)
    -> AppPipeline
  {
    let log = Log.logger(.delivery)
    let store = try SQLiteHistoryStore.open(
      at: StoreLocation.databaseURL(applicationSupport: applicationSupport()),
      server: settings?.origin ?? localOrigin, clock: services.clock)
    let poster = UserNotificationPoster(
      center: services.center, images: images(settings: settings),
      log: { log.info("\($0, privacy: .private)") })
    let delivery = DeliveryService(
      poster: poster, history: store, inbox: store, config: services.config,
      clock: services.clock, log: { log.info("\($0, privacy: .private)") })

    await delivery.start()
    await poster.restoreDeliveredCategories(inbox: store, config: services.config.load())
    await delivery.reconcile()
    let responses = responseHandler(store: store, delivery: delivery, services: services)
    await services.router.use { await responses.handle($0) }

    var supervisor: StreamSupervisor?
    if let settings {
      supervisor = StreamSupervisor(
        ports: ports(settings: settings, store: store, delivery: delivery, services: services),
        options: options(settings: settings, delivery: delivery))
      await supervisor?.start()
    }
    return AppPipeline(
      services: services, store: store, delivery: delivery, supervisor: supervisor,
      attachments: attachments(settings: settings))
  }

  private init(
    services: AppServices, store: SQLiteHistoryStore, delivery: DeliveryService,
    supervisor: StreamSupervisor?, attachments: any AttachmentFetching
  ) {
    self.services = services
    self.attachments = attachments
    self.store = store
    self.delivery = delivery
    self.supervisor = supervisor
    retention = Task { [store, clock = services.clock] in
      await Self.pruneForever(store: store, clock: clock)
    }
  }

  /// The router is detached first, so a click in the next moments cannot reach a stopping
  /// delivery; then supervisor, retention loop, delivery, and last the store is closed.
  func shutdown() async {
    await services.router.use(nil)
    await supervisor?.stop()
    retention.cancel()
    await retention.value
    await delivery.shutdown()
    do throws(NtfyError) {
      try store.close()
    } catch {
      Log.logger(.store).error("history not closed: \(String(describing: error), privacy: .public)")
    }
  }

  // MARK: Wiring

  /// Local messages carry no attachment, so the local pipeline fetches nothing.
  private static func images(settings: Settings?) -> any ImageFetching {
    guard let settings else { return NoImageFetcher() }
    let token = settings.token
    return URLSessionImageFetcher(
      server: settings.url, token: { token }, allowInsecure: settings.allowInsecure)
  }

  /// The History window previews attachments of the configured server; the local pipeline has
  /// none.
  private static func attachments(settings: Settings?) -> any AttachmentFetching {
    guard let settings else { return NoAttachmentFetcher() }
    let token = settings.token
    return URLSessionAttachmentFetcher(
      server: settings.url, token: { token }, allowInsecure: settings.allowInsecure)
  }

  private static func responseHandler(
    store: SQLiteHistoryStore, delivery: DeliveryService, services: AppServices
  ) -> ResponseHandler {
    let log = Log.logger(.delivery)
    return ResponseHandler(
      delivery: delivery, inbox: store, config: services.config, opener: WorkspaceLinkOpener(),
      presenter: RoutedHistoryPresenter(windows: services.windows), confirmer: AlertConfirmer(),
      runner: URLSessionHTTPActionRunner(allowPrivateNetwork: {
        await services.config.load().allowPrivateNetworkActions
      }), log: { log.info("\($0, privacy: .private)") })
  }

  private static func ports(
    settings: Settings, store: SQLiteHistoryStore, delivery: DeliveryService,
    services: AppServices
  ) -> StreamSupervisor.Ports {
    let log = Log.logger(.stream)
    let diagnostics: @Sendable (String) -> Void = { log.debug("\($0, privacy: .private)") }
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
    options.log = { log.info("\($0, privacy: .private)") }
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
        if dropped > 0 { log.info("pruned \(dropped, privacy: .private) history rows") }
      } catch {
        log.error("history not pruned: \(String(describing: error), privacy: .private)")
      }
      do { try await clock.sleep(for: retentionInterval) } catch { return }
    }
  }

  static func applicationSupport() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support", directoryHint: .isDirectory)
  }
}

extension AppPipeline {
  /// What the socket handler may use of this pipeline.
  var handles: PipelineHandles {
    PipelineHandles(
      store: store, delivery: delivery, supervisor: supervisor, attachments: attachments)
  }
}
