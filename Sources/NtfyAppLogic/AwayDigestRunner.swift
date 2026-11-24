import Foundation
import NtfyCore

/// Posts the digest of what was missed when the user comes back to the Mac or opens the History
/// window. It follows `SystemEvents`, asks `ReturnPolicy` whether a digest is due, builds it with
/// `DigestBuilder` and shows it through the poster. It never touches delivery: a failing model
/// costs a plainer text, a failing poster costs the digest, nothing else.
public actor AwayDigestRunner {
  private let events: any SystemEvents
  private let config: any ConfigStore
  private let inbox: any HistoryInbox
  private let summarizers: SummarizerProvider
  private let poster: any NotificationPoster
  private let clock: any Clock
  private let log: @Sendable (String) -> Void
  private var policy: ReturnPolicy
  private var building = false
  private var task: Task<Void, Never>?

  public init(
    events: any SystemEvents, config: any ConfigStore, inbox: any HistoryInbox,
    summarizers: SummarizerProvider, poster: any NotificationPoster, clock: any Clock,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.events = events
    self.config = config
    self.inbox = inbox
    self.summarizers = summarizers
    self.poster = poster
    self.clock = clock
    self.log = log
    policy = ReturnPolicy(now: clock.now())
  }

  /// Starts following the system events. Idempotent.
  public func start() {
    guard task == nil else { return }
    let stream = events.events()
    task = Task { [weak self] in
      for await event in stream {
        await self?.process(event)
      }
    }
  }

  public func stop() async {
    task?.cancel()
    await task?.value
    task = nil
  }

  /// The History window or the menu bar was opened.
  public func windowOpened() async {
    let settings = await currentConfig().summary
    guard let since = policy.windowOpened(now: clock.now(), settings: settings) else { return }
    await post(since: since)
  }

  /// One system event; `start` feeds it from the stream, tests call it directly.
  public func process(_ event: SystemEvent) async {
    let settings = await currentConfig().summary
    guard let since = policy.handle(event, now: clock.now(), settings: settings) else { return }
    await post(since: since)
  }

  private func currentConfig() async -> Config {
    (try? await config.load()) ?? Config()
  }

  private func post(since: Date) async {
    guard !building else { return }
    building = true
    defer { building = false }
    let config = await currentConfig()
    let builder = DigestBuilder(inbox: inbox, log: log)
    let messages: [StoredMessage]
    do throws(NtfyError) {
      messages = try await builder.collect(since: since, config: config)
    } catch {
      log("digest not collected: \(error)")
      return
    }
    guard messages.count >= config.summary.minMessages else { return }
    let summarizer = await summarizers.summarizer(for: config)
    let digest = await builder.digest(of: messages, config: config, summarizer: summarizer)
    do throws(NtfyError) {
      try await poster.postDigest(title: digest.title, body: digest.text)
      policy.markChecked(at: clock.now())
    } catch {
      log("digest not posted: \(error)")
    }
  }
}
