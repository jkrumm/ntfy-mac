import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting

/// A `HistoryModel` over a pipeline of fakes, on a UTC calendar, with a bounded wait.
@MainActor
struct HistoryModelRig {
  nonisolated static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
  }()

  let source = ManualPipelineSource()
  let opener = RecordingLinkOpener()
  let pipeline: PipelineFixture
  let model: HistoryModel

  init(pipeline: PipelineFixture = PipelineFixture(), pageSize: Int = 50) {
    self.pipeline = pipeline
    source.set(pipeline.handles)
    model = HistoryModel(
      source: source, opener: opener, clock: pipeline.clock, config: pipeline.config,
      calendar: Self.utc,
      pageSize: pageSize, searchDebounce: .milliseconds(300))
  }

  /// Polls `condition` between yields, up to a hard cap.
  func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200_000 {
      if condition() { return true }
      await Task.yield()
    }
    return false
  }

  /// Stores a message `age` seconds before the clock.
  @discardableResult
  func add(
    _ id: String, topic: String = "alerts", age: TimeInterval = 0, title: String? = nil,
    body: String? = nil, priority: Priority = .default, tags: [String] = [],
    click: URL? = nil, sequenceID: String? = nil, attachment: MessageAttachment? = nil,
    actions: [MessageAction] = [], contentType: String? = nil
  ) async -> NtfyMessage {
    let message = NtfyMessage(
      id: id, topic: topic, time: pipeline.clock.now().addingTimeInterval(-age), title: title,
      body: body ?? "body \(id)", priority: priority, tags: tags, click: click,
      sequenceID: sequenceID, attachment: attachment, actions: actions, contentType: contentType)
    _ = try? await pipeline.history.append(message)
    return message
  }

  /// Starts the model and waits for the first read of the history.
  func start() async {
    model.start()
    _ = await eventually { model.isAvailable }
    await model.refresh()
  }

  func ids() -> [String] { model.rows.map(\.key.id) }
}
