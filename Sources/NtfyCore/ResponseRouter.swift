/// Carries notification responses to whichever handler is installed right now.
///
/// The system delivers a click that launched the app before the pipeline exists, and a rebuild
/// leaves a gap too. Responses that arrive without a handler wait (the newest `capacity` ones)
/// and are replayed in order when one is installed.
public actor ResponseRouter {
  public typealias Handler = @Sendable (NotificationResponse) async -> Void

  public static let capacity = 16

  private var handler: Handler?
  private var buffer: [NotificationResponse] = []
  private var isDraining = false
  private let log: @Sendable (String) -> Void

  public init(log: @escaping @Sendable (String) -> Void = { _ in }) {
    self.log = log
  }

  /// Installs the handler (or removes it with `nil`) and replays what waited.
  public func use(_ handler: Handler?) async {
    self.handler = handler
    await drain()
  }

  public func handle(_ response: NotificationResponse) async {
    buffer.append(response)
    if buffer.count > Self.capacity {
      buffer.removeFirst()
      log("response dropped: more than \(Self.capacity) waiting for a handler")
    }
    await drain()
  }

  /// One loop at a time keeps responses in order, also when new ones arrive while it runs.
  private func drain() async {
    guard !isDraining else { return }
    isDraining = true
    defer { isDraining = false }
    while let current = handler, !buffer.isEmpty {
      await current(buffer.removeFirst())
    }
  }
}
