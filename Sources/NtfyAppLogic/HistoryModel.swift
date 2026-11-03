import Foundation
import NtfyCore
import Observation

/// What the History window shows and does: the topics with unread counts, the message log of the
/// selected topic (filtered, paged, grouped by day), the selected message in full, a composer
/// that publishes a new message, and the actions on a message.
///
/// Like `AppModel` it follows the running pipeline through `PipelineSource`: the history change
/// signal refreshes it, and it attaches again when a pipeline is built or torn down. A message
/// becomes read when it is selected; loading the list never does. Everything is plain values; the view reads the
/// properties and calls the actions, and owns the AppKit parts (save panel, Quick Look,
/// consuming `WindowRouter`).
@MainActor @Observable
public final class HistoryModel {
  public static let defaultPageSize = 50
  public static let defaultSearchDebounce: Duration = .milliseconds(300)

  // MARK: State

  /// Every topic with messages, newest first, with its unread count.
  public private(set) var topics: [TopicSummary] = []
  /// Topics with an unacknowledged message that needs one, for the sidebar's marker.
  public private(set) var urgentTopics: Set<String> = []
  /// The messages matching the filters, as far as loaded (`loadMore()` extends it).
  public private(set) var rows: [MessageRow] = []
  /// `rows` grouped by calendar day, newest first.
  public private(set) var days: [DayGroup] = []
  /// How many messages match the filters, loaded or not ("N results").
  public private(set) var resultCount = 0
  /// The selected message, even when the filters hide it.
  public private(set) var selection: MessageKey?
  /// The selected message in full; nil without a selection or once the message is gone.
  public private(set) var detail: MessageDetail?
  /// Fetch state of the attachments that were loaded, by message.
  public internal(set) var attachments: [MessageKey: AttachmentState] = [:]
  /// A pipeline (and so a history) is running. False while one is rebuilt or before the first.
  public private(set) var isAvailable = false
  /// Which priorities need an acknowledgement; follows the re-alert minimum in the config.
  public private(set) var acknowledgePolicy = AcknowledgePolicy()

  // MARK: Filters

  /// nil shows every topic.
  public var selectedTopic: String? {
    didSet {
      guard selectedTopic != oldValue else { return }
      filtersChanged()
    }
  }
  /// Free text over title and body. Applied after a pause in typing; the store sanitises it.
  public var searchText = "" {
    didSet { if searchText != oldValue { searchChanged() } }
  }
  /// Only messages at or above this priority; nil for all.
  public var minPriority: Priority? {
    didSet { if minPriority != oldValue { filtersChanged() } }
  }
  public var dateFilter = HistoryDateFilter.all {
    didSet { if dateFilter != oldValue { filtersChanged() } }
  }
  public var unreadOnly = false {
    didSet { if unreadOnly != oldValue { filtersChanged() } }
  }

  // MARK: Composer

  /// Where the composer gets its publisher. The app root sets it; without one a send fails with
  /// a message instead of doing nothing.
  @ObservationIgnored public var publisher: (any PublisherProviding)?
  public var composerPriority = Priority.default
  public internal(set) var composerState = ComposerState.idle
  /// The topic a new message goes to; nil follows the selected topic (see `openComposer()`).
  public var composerTopic: String? {
    didSet { if composerTopic != oldValue { clearComposerFailure() } }
  }
  /// The text of the new message. Editing it clears a failed send's error.
  public var draft = "" {
    didSet { if draft != oldValue { clearComposerFailure() } }
  }
  /// Topics from the subscription settings, which may not have a message yet.
  var configuredTopics: [String] = []

  // MARK: Derived

  public var hasMore: Bool { rows.count < resultCount }
  public var totalUnread: Int { topics.reduce(0) { $0 + $1.unread } }
  public var totalMessages: Int { topics.reduce(0) { $0 + $1.total } }
  /// Any filter narrows the list (a topic counts).
  public var isFiltering: Bool {
    selectedTopic != nil || !trimmedSearch.isEmpty || minPriority != nil || dateFilter != .all
      || unreadOnly
  }

  // MARK: Collaborators

  @ObservationIgnored let source: any PipelineSource
  @ObservationIgnored let opener: any LinkOpening
  @ObservationIgnored let clock: any NtfyCore.Clock
  @ObservationIgnored let config: any ConfigStore
  @ObservationIgnored let calendar: Calendar
  @ObservationIgnored let pageSize: Int
  @ObservationIgnored let searchDebounce: Duration
  @ObservationIgnored let log: @Sendable (String) -> Void
  @ObservationIgnored var handles: PipelineHandles?
  @ObservationIgnored var loadedLimit: Int
  @ObservationIgnored var attachmentTasks: [MessageKey: Task<Void, Never>] = [:]
  @ObservationIgnored private var lastRefresh: Task<Void, Never>?
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var tasks: [Task<Void, Never>] = []
  @ObservationIgnored private var pipelineTasks: [Task<Void, Never>] = []

  public init(
    source: any PipelineSource, opener: any LinkOpening, clock: any NtfyCore.Clock,
    config: any ConfigStore, calendar: Calendar = .current,
    pageSize: Int = HistoryModel.defaultPageSize,
    searchDebounce: Duration = HistoryModel.defaultSearchDebounce,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.source = source
    self.opener = opener
    self.clock = clock
    self.config = config
    self.calendar = calendar
    self.pageSize = max(pageSize, 1)
    self.searchDebounce = searchDebounce
    self.log = log
    loadedLimit = max(pageSize, 1)
  }

  // MARK: Lifecycle

  /// Subscribes first, then attaches, so a rebuild during startup is not missed. Idempotent.
  public func start() {
    guard tasks.isEmpty else { return }
    let rebuilds = source.rebuilds()
    tasks = [
      Task {
        await attach()
        for await _ in rebuilds { await attach() }
      }
    ]
  }

  /// Stops following and cancels pending work. The last values stay readable.
  public func stop() {
    for task in tasks + pipelineTasks { task.cancel() }
    tasks = []
    pipelineTasks = []
    searchTask?.cancel()
    searchTask = nil
    for key in Array(attachmentTasks.keys) { cancelAttachment(for: key) }
    lastRefresh = nil
  }

  private func attach() async {
    let next = await source.current()
    for task in pipelineTasks { task.cancel() }
    pipelineTasks = []
    handles = next
    isAvailable = next != nil
    guard let next else { return }
    let signals = next.changes.changes()
    pipelineTasks.append(
      Task {
        for await _ in signals { await refresh() }
      })
    await refresh()
  }

  // MARK: Reading

  /// Re-reads topics, the list and the selection. Calls run one after the other, so a late
  /// result never overwrites a newer one, and a caller that awaits sees its own state.
  public func refresh() async {
    let previous = lastRefresh
    let run = Task {
      await previous?.value
      await reload()
    }
    lastRefresh = run
    await run.value
  }

  /// Shows the next page of the list.
  public func loadMore() async {
    guard hasMore else { return }
    loadedLimit += pageSize
    await refresh()
  }

  private func reload() async {
    guard let inbox = handles?.inbox else { return }
    do throws(NtfyError) {
      let query = currentQuery(limit: loadedLimit)
      let stored = try await config.load()
      let policy = AcknowledgePolicy(config: stored)
      let summaries = try await inbox.topics()
      let urgent = Set(
        try await inbox.unacknowledged(minPriority: policy.minPriority).map(\.message.topic))
      let count = try await inbox.count(query)
      let entries = try await inbox.entries(query)
      var shown: MessageDetail?
      if let key = selection {
        shown = try await inbox.message(topic: key.topic, id: key.id).map {
          MessageDetail($0, now: clock.now())
        }
      }
      acknowledgePolicy = policy
      configuredTopics = stored.extraTopics
      topics = summaries
      urgentTopics = urgent
      resultCount = count
      rows = entries.map(MessageRow.init)
      days = HistoryGrouping.days(of: rows, calendar: calendar)
      if selection != nil {
        detail = shown
        if shown == nil { clearSelection() }
      }
    } catch {
      log("history not read: \(error)")
    }
  }

  // MARK: Filters

  var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

  func currentQuery(limit: Int, offset: Int = 0, until: Date? = nil) -> HistoryQuery {
    HistoryQuery(
      topic: selectedTopic, unreadOnly: unreadOnly,
      text: trimmedSearch.isEmpty ? nil : trimmedSearch,
      minPriority: minPriority, since: dateFilter.start(from: clock.now(), calendar: calendar),
      until: until, limit: limit, offset: offset)
  }

  /// Back to the first page, re-read.
  private func filtersChanged() {
    loadedLimit = pageSize
    Task { await refresh() }
  }

  /// Typing waits for a pause on the injected clock; clearing the field applies at once.
  private func searchChanged() {
    searchTask?.cancel()
    let wait = trimmedSearch.isEmpty ? nil : searchDebounce
    searchTask = Task {
      if let wait {
        do { try await clock.sleep(for: wait) } catch { return }
      }
      loadedLimit = pageSize
      await refresh()
    }
  }

  /// Drops every filter and the search text, so nothing hides a message.
  public func resetFilters() {
    searchTask?.cancel()
    searchTask = nil
    searchText = ""
    minPriority = nil
    dateFilter = .all
    unreadOnly = false
    selectedTopic = nil
  }

  // MARK: Selection

  /// For a list's selection binding, which cannot await: starts `select` and returns.
  public func setSelection(_ key: MessageKey?) {
    Task { await select(key) }
  }

  /// Shows the message in the detail pane and marks it read. Selecting nothing clears the pane.
  public func select(_ key: MessageKey?) async {
    guard key != selection else { return }
    guard let key else {
      clearSelection()
      return
    }
    selection = key
    detail = nil
    await refresh()
    guard selection == key, let shown = detail, !shown.isRead else { return }
    await markRead(key)
  }

  /// The window was asked to show this message (a notification click through `WindowRouter`):
  /// every filter is dropped, its topic is selected and the message is selected, so it is in the
  /// list. The view takes the key from the router and calls this.
  public func apply(selection key: MessageKey) async {
    resetFilters()
    selectedTopic = key.topic
    loadedLimit = pageSize
    await select(nil)
    await select(key)
  }

  func clearSelection() {
    selection = nil
    detail = nil
  }
}
