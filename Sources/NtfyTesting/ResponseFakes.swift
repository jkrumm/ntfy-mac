import Foundation
import NtfyCore

/// Records links instead of opening them.
public actor RecordingLinkOpener: LinkOpening {
  public private(set) var opened: [URL] = []
  private let succeeds: Bool

  public init(succeeds: Bool = true) {
    self.succeeds = succeeds
  }

  public func open(_ url: URL) -> Bool {
    opened.append(url)
    return succeeds
  }
}

public actor RecordingHistoryPresenter: HistoryPresenting {
  public private(set) var shown: [MessageRef] = []

  public init() {}

  public func show(topic: String, id: String) {
    shown.append(MessageRef(topic: topic, id: id))
  }
}

/// Answers every confirmation the same way and remembers what it was asked.
public actor ScriptedActionConfirmer: ActionConfirming {
  public struct Question: Sendable, Hashable {
    public let reason: String
    public let label: String
  }

  public private(set) var asked: [Question] = []
  private let answer: Bool

  public init(answer: Bool) {
    self.answer = answer
  }

  public func confirm(_ reason: String, action label: String) -> Bool {
    asked.append(Question(reason: reason, label: label))
    return answer
  }
}

/// Records the requests it was asked to send; fails every one when given an error.
public actor RecordingHTTPActionRunner: HTTPActionRunning {
  public private(set) var calls: [HTTPCall] = []
  private let failure: NtfyError?

  public init(failingWith failure: NtfyError? = nil) {
    self.failure = failure
  }

  public func run(_ call: HTTPCall) throws(NtfyError) {
    calls.append(call)
    if let failure { throw failure }
  }
}

/// Hands out a fixed file (or nothing) for every image.
public actor StubImageFetcher: ImageFetching {
  public private(set) var requested: [URL] = []
  private let file: URL?

  public init(file: URL? = nil) {
    self.file = file
  }

  public func fetch(_ url: URL) -> URL? {
    requested.append(url)
    return file
  }
}

/// Records what a response asked of the delivery service.
public actor RecordingResponseDelivery: ResponseDelivering {
  public private(set) var acknowledged: [MessageRef] = []
  public private(set) var opened: [MessageRef] = []

  public init() {}

  public func acknowledge(topic: String, id: String) {
    acknowledged.append(MessageRef(topic: topic, id: id))
  }

  public func opened(topic: String, id: String) {
    opened.append(MessageRef(topic: topic, id: id))
  }
}

/// A permission that tests set by hand; `requestAuthorization` moves it to `afterRequest`.
public actor InMemoryNotificationPermission: NotificationPermissionProviding {
  public private(set) var requests = 0
  private var state: NotificationPermission
  private let afterRequest: NotificationPermission

  public init(
    _ state: NotificationPermission = NotificationPermission(authorization: .notDetermined),
    afterRequest: NotificationPermission = .allowed
  ) {
    self.state = state
    self.afterRequest = afterRequest
  }

  public func set(_ state: NotificationPermission) {
    self.state = state
  }

  public func current() -> NotificationPermission { state }

  public func requestAuthorization() -> NotificationPermission {
    requests += 1
    if state.authorization == .notDetermined { state = afterRequest }
    return state
  }
}

/// Answers lookups from a table; hosts it does not know fail, like an unresolvable name.
public struct StubHostResolver: HostResolving {
  private let table: [String: [String]]

  public init(_ table: [String: [String]] = [:]) {
    self.table = table
  }

  /// Every host resolves to the public address 8.8.8.8.
  public static let public8888 = StubHostResolver(["*": ["8.8.8.8"]])

  public func addresses(of host: String) async -> [String]? {
    table[host.lowercased()] ?? table["*"]
  }
}
