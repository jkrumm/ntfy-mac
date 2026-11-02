import Foundation

/// What the user did with a notification, as the platform adapter reports it. The ids come from
/// outside the process and are never trusted: `ResponseHandler` looks everything up again.
public struct NotificationResponse: Sendable, Hashable {
  public enum Kind: Sendable, Hashable {
    /// The notification body was clicked.
    case body
    /// A button was pressed.
    case button(id: String)
    /// The user swiped the notification away; nothing happens.
    case dismissed
  }

  public let ref: MessageRef
  public let kind: Kind

  public init(ref: MessageRef, kind: Kind) {
    self.ref = ref
    self.kind = kind
  }
}

/// How a response ended; the handler never throws.
public enum ResponseOutcome: Sendable, Hashable {
  case completed
  /// Nothing to do: dismissed, or the message or button is unknown.
  case ignored(String)
  /// The user said no to the confirmation.
  case declined
  /// The policy forbids the action now.
  case denied(String)
  case failed(NtfyError)
}

/// The part of `DeliveryService` that responses need.
public protocol ResponseDelivering: Sendable {
  func acknowledge(topic: String, id: String) async
  /// Marks the message read and acknowledged.
  func opened(topic: String, id: String) async
}

extension DeliveryService: ResponseDelivering {}

/// Turns notification clicks and button presses into effects.
///
/// Everything is derived again from the history and the current config, so a forged or stale id
/// is a logged no-op and a config change since posting is honoured.
public struct ResponseHandler: Sendable {
  let delivery: any ResponseDelivering
  let inbox: any HistoryInbox
  let config: any ConfigStore
  let opener: any LinkOpening
  let presenter: any HistoryPresenting
  let confirmer: any ActionConfirming
  let runner: any HTTPActionRunning
  let log: @Sendable (String) -> Void

  public init(
    delivery: any ResponseDelivering, inbox: any HistoryInbox, config: any ConfigStore,
    opener: any LinkOpening, presenter: any HistoryPresenting, confirmer: any ActionConfirming,
    runner: any HTTPActionRunning, log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.delivery = delivery
    self.inbox = inbox
    self.config = config
    self.opener = opener
    self.presenter = presenter
    self.confirmer = confirmer
    self.runner = runner
    self.log = log
  }

  @discardableResult
  public func handle(_ response: NotificationResponse) async -> ResponseOutcome {
    if case .dismissed = response.kind { return .ignored("dismissed") }
    let ref = response.ref
    guard let stored = await storedMessage(ref) else {
      return ignored("unknown message \(ref.topic)/\(ref.id)")
    }
    let settings = await currentConfig()
    let content = DeliveryPolicy.content(for: stored.message, config: settings)
    switch response.kind {
    case .dismissed:
      return .ignored("dismissed")
    case .body:
      return await open(content)
    case .button(let id):
      guard let button = content.buttons.first(where: { $0.id == id }) else {
        return ignored("unknown button \(id) on \(ref.topic)/\(ref.id)")
      }
      return await press(button, of: stored.message, config: settings)
    }
  }

  // MARK: Body

  private func open(_ content: NotificationContent) async -> ResponseOutcome {
    let ref = content.messageRef
    var opened = false
    if case .openURL(let url) = content.bodyAction { opened = await openLink(url) }
    if !opened { await presenter.show(topic: ref.topic, id: ref.id) }
    await delivery.opened(topic: ref.topic, id: ref.id)
    return .completed
  }

  // MARK: Buttons

  private func press(
    _ button: NotificationButton, of message: NtfyMessage, config: Config
  ) async -> ResponseOutcome {
    switch button.action {
    case .acknowledge:
      await delivery.acknowledge(topic: message.topic, id: message.id)
      return .completed
    case .openURL(let url):
      guard await openLink(url) else { return .failed(.invalidResponse("link not opened")) }
      await delivery.opened(topic: message.topic, id: message.id)
      return .completed
    case .http(let call, let confirmation):
      return await send(
        call, button: button, confirmation: confirmation, message: message, config: config)
    }
  }

  private func send(
    _ call: HTTPCall, button: NotificationButton, confirmation: String?, message: NtfyMessage,
    config: Config
  ) async -> ResponseOutcome {
    guard
      let action = message.actions.first(where: {
        $0.kind == .http && $0.url == call.url && $0.label == button.title
      })
    else { return ignored("no http action behind \(button.id)") }
    var reason = confirmation
    switch ActionPolicy.evaluate(action, config: config) {
    case .deny(let why):
      log("action \(button.id) denied: \(why)")
      return .denied(why)
    case .confirm(let why):
      reason = reason ?? why
    case .allow:
      break
    }
    if let reason, !(await confirmer.confirm(reason, action: button.title)) {
      return .declined
    }
    do throws(NtfyError) {
      try await runner.run(call)
    } catch {
      log("action \(button.id) failed: \(error)")
      return .failed(error)
    }
    if action.clear { await delivery.acknowledge(topic: message.topic, id: message.id) }
    return .completed
  }

  // MARK: Helpers

  /// Opens `url` if the policy still allows it.
  private func openLink(_ url: URL) async -> Bool {
    guard let safe = URLPolicy.openable(url) else {
      log("link refused by policy")
      return false
    }
    return await opener.open(safe)
  }

  private func storedMessage(_ ref: MessageRef) async -> StoredMessage? {
    do throws(NtfyError) {
      return try await inbox.message(topic: ref.topic, id: ref.id)
    } catch {
      log("history lookup failed: \(error)")
      return nil
    }
  }

  private func currentConfig() async -> Config {
    do throws(NtfyError) {
      return try await config.load()
    } catch {
      log("config not loaded, using defaults: \(error)")
      return Config()
    }
  }

  private func ignored(_ reason: String) -> ResponseOutcome {
    log(reason)
    return .ignored(reason)
  }
}
