import Foundation
import NtfyCore
import Observation

/// What the menu bar and the windows show, and the actions they trigger.
///
/// It follows the running pipeline through `PipelineSource` and attaches again each time one is
/// built or torn down: the supervisor's status stream and the history change signal feed it
/// while one runs. The pause (`Config.pausedUntil`) follows the config file through
/// `configChanges` (the file watcher in production, so a `ntfy-mac pause` from a terminal shows
/// up), through a re-read on every history signal and rebuild, and through a timer for its end.
/// Everything is plain values; views read the properties and call the actions.
@MainActor @Observable
public final class AppModel {
  public static let defaultRecentLimit = 8
  /// Unread messages are counted up to this; more shows as "99+".
  static let unreadCountCap = 100

  public private(set) var connection = ConnectionSummary.connecting
  public private(set) var unreadCount = 0
  /// Messages that need an acknowledgement and have none, in the whole history. Lower
  /// priorities never count (`acknowledgePolicy`).
  public private(set) var unacknowledgedCount = 0
  /// Which priorities need an acknowledgement; follows the re-alert minimum in the config.
  public private(set) var acknowledgePolicy = AcknowledgePolicy()
  /// Newest first.
  public private(set) var recent: [MessageRow] = []
  /// The end of a pause that is still running, nil when notifications are on.
  public private(set) var pausedUntil: Date?
  /// Nil until the first check.
  public private(set) var permission: NotificationPermission?
  /// What the meeting detection reports, whatever the mode is. Follows the injected provider.
  public private(set) var detectedMeeting = MeetingState.inactive
  /// The meeting settings as last read from the config; an override that has ended is dropped.
  public private(set) var meetingSettings = MeetingSettings()
  /// Why the last "I am presenting" change could not be stored; cleared by the next one that
  /// works.
  public internal(set) var presentingError: String?

  @ObservationIgnored let source: any PipelineSource
  @ObservationIgnored let meeting: any MeetingStateProviding
  @ObservationIgnored let config: any ConfigStore
  @ObservationIgnored let permissions: any NotificationPermissionProviding
  @ObservationIgnored let clock: any NtfyCore.Clock
  @ObservationIgnored let configChanges: @Sendable () -> AsyncStream<Void>
  @ObservationIgnored let calendar: Calendar
  @ObservationIgnored let recentLimit: Int
  @ObservationIgnored let log: @Sendable (String) -> Void
  @ObservationIgnored var handles: PipelineHandles?
  @ObservationIgnored private var lastRefresh: Task<Void, Never>?
  @ObservationIgnored private var tasks: [Task<Void, Never>] = []
  @ObservationIgnored private var pipelineTasks: [Task<Void, Never>] = []
  @ObservationIgnored private var expiry: Task<Void, Never>?
  @ObservationIgnored private var presentingExpiry: Task<Void, Never>?

  public init(
    source: any PipelineSource, meeting: any MeetingStateProviding, config: any ConfigStore,
    permissions: any NotificationPermissionProviding, clock: any NtfyCore.Clock,
    configChanges: @escaping @Sendable () -> AsyncStream<Void>,
    calendar: Calendar = .current, recentLimit: Int = AppModel.defaultRecentLimit,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.source = source
    self.meeting = meeting
    self.config = config
    self.permissions = permissions
    self.clock = clock
    self.configChanges = configChanges
    self.calendar = calendar
    self.recentLimit = recentLimit
    self.log = log
  }

  // MARK: Derived

  public var menuBarIcon: MenuBarIcon {
    if case .needsAttention = connection { return .attention }
    if pausedUntil != nil { return .paused }
    if connection.isDisconnected { return .offline }
    return unreadCount > 0 ? .unread : .idle
  }

  /// The unread count for the menu bar, nil when there is nothing unread.
  public var badgeText: String? {
    guard unreadCount > 0 else { return nil }
    return unreadCount >= Self.unreadCountCap ? "99+" : String(unreadCount)
  }

  /// Notifications are held back and the end is not a time but "until I resume".
  public var isPausedIndefinitely: Bool { pausedUntil.map(PauseWindow.isIndefinite) ?? false }

  /// Notifications are held back because of a meeting: the override, or a detected meeting with
  /// the mode on.
  public var meetingActive: Bool { meetingReason != nil }

  /// Why, nil when no meeting holds notifications back. The override wins.
  public var meetingReason: MeetingReason? {
    meetingSettings.effectiveState(detected: detectedMeeting, at: clock.now()).reason
  }

  /// The meeting mode as last read from the config.
  public var meetingMode: MeetingMode { meetingSettings.mode }

  /// The end of the manual "I am presenting" override while it runs, nil when it is off.
  public var presentingUntil: Date? { meetingSettings.presentingUntil }

  /// The manual override is on.
  public var isPresentingOverride: Bool { presentingUntil != nil }

  // MARK: Lifecycle

  /// Subscribes first, then attaches, so a rebuild during startup is not missed. Idempotent.
  public func start() {
    guard tasks.isEmpty else { return }
    let rebuilds = source.rebuilds()
    let configs = configChanges()
    tasks = [
      Task {
        await attach()
        for await _ in rebuilds { await attach() }
      },
      Task {
        for await _ in configs { await refresh() }
      },
      Task { await refreshPermission() },
    ]
    let meetings = meeting.changes()
    tasks.append(
      Task {
        for await state in meetings { detectedMeeting = state }
      })
  }

  /// Stops following. The last values stay readable.
  public func stop() {
    for task in tasks + pipelineTasks { task.cancel() }
    tasks = []
    pipelineTasks = []
    expiry?.cancel()
    expiry = nil
    presentingExpiry?.cancel()
    presentingExpiry = nil
    lastRefresh = nil
  }

  /// Follows whatever pipeline `source` has now.
  private func attach() async {
    let next = await source.current()
    for task in pipelineTasks { task.cancel() }
    pipelineTasks = []
    handles = next
    guard let next else {
      connection = .connecting
      return
    }
    if let supervisor = next.supervisor {
      pipelineTasks.append(
        Task {
          for await status in supervisor.status { connection = ConnectionSummary(status) }
        })
    } else {
      connection = .notConfigured
    }
    let signals = next.changes.changes()
    pipelineTasks.append(
      Task {
        for await _ in signals { await refresh() }
      })
    await refresh()
  }

  // MARK: Reading

  /// Re-reads the pause, the recent messages and the counts. Calls run one after the other, so
  /// a late result never overwrites a newer one, and a caller that awaits sees its own state.
  public func refresh() async {
    let previous = lastRefresh
    let run = Task {
      await previous?.value
      await reload()
    }
    lastRefresh = run
    await run.value
  }

  private func reload() async {
    let until = await activePause()
    pausedUntil = until
    scheduleExpiry(of: until)
    await readMeeting()
    guard let inbox = handles?.inbox else { return }
    do throws(NtfyError) {
      let rows = try await inbox.entries(HistoryQuery(limit: recentLimit))
      let unread = try await inbox.entries(
        HistoryQuery(unreadOnly: true, limit: Self.unreadCountCap))
      let policy = AcknowledgePolicy(config: try await config.load())
      let unacknowledged = try await inbox.unacknowledged(minPriority: policy.minPriority)
      acknowledgePolicy = policy
      recent = rows.map(MessageRow.init)
      unreadCount = unread.count
      unacknowledgedCount = unacknowledged.count
    } catch {
      log("history not read: \(error)")
    }
  }

  /// Asks the system what notifications may do. Call it when the app becomes active and when
  /// the menu opens.
  public func refreshPermission() async {
    permission = await permissions.current()
  }

  private func activePause() async -> Date? {
    do throws(NtfyError) {
      let stored = try await config.load().pausedUntil
      return stored.flatMap { $0 > clock.now() ? $0 : nil }
    } catch {
      log("config not read: \(error)")
      return pausedUntil
    }
  }

  /// Re-reads when a timed pause ends, so the menu does not show a pause that is over.
  private func scheduleExpiry(of until: Date?) {
    expiry?.cancel()
    expiry = nil
    guard let until, !PauseWindow.isIndefinite(until) else { return }
    let wait = max(until.timeIntervalSince(clock.now()), 0)
    expiry = Task {
      do { try await clock.sleep(for: .seconds(wait)) } catch { return }
      await refresh()
    }
  }
}

extension AppModel {
  /// Re-reads the meeting mode and the override from the config, and arms the end of a timed
  /// override.
  func readMeeting() async {
    do throws(NtfyError) {
      var settings = try await config.load().meeting
      settings.presentingUntil = settings.presentingUntil.flatMap { $0 > clock.now() ? $0 : nil }
      meetingSettings = settings
      schedulePresentingExpiry(of: settings.presentingUntil)
    } catch {
      log("config not read: \(error)")
    }
  }

  private func schedulePresentingExpiry(of until: Date?) {
    presentingExpiry?.cancel()
    presentingExpiry = nil
    guard let until, !PauseWindow.isIndefinite(until) else { return }
    let wait = max(until.timeIntervalSince(clock.now()), 0)
    presentingExpiry = Task {
      do { try await clock.sleep(for: .seconds(wait)) } catch { return }
      await refresh()
    }
  }
}
