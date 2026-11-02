import Foundation

/// Identifies a stored message for callbacks (click, acknowledge).
public struct MessageRef: Sendable, Hashable, Codable {
  public let topic: String
  public let id: String

  public init(topic: String, id: String) {
    self.topic = topic
    self.id = id
  }
}

/// A prepared HTTP request behind an `http` action button.
public struct HTTPCall: Sendable, Hashable {
  public let url: URL
  public let method: String
  public let headers: [String: String]
  public let body: String?

  public init(url: URL, method: String, headers: [String: String], body: String?) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }
}

/// What a notification button does.
public enum ButtonAction: Sendable, Hashable {
  /// Marks the message acknowledged.
  case acknowledge
  case openURL(URL)
  /// `confirmation` is the reason to ask the user first, nil when the request may run at once.
  case http(HTTPCall, confirmation: String?)
}

public struct NotificationButton: Sendable, Hashable {
  /// Unique within one notification.
  public let id: String
  public let title: String
  public let action: ButtonAction

  public init(id: String, title: String, action: ButtonAction) {
    self.id = id
    self.title = title
    self.action = action
  }
}

/// What clicking the notification body does. Either way the message is marked read.
public enum BodyAction: Sendable, Hashable {
  case openURL(URL)
  case openHistory
}

/// Everything a poster needs to show one message.
public struct NotificationContent: Sendable, Hashable {
  /// Stable per notification (`topic/sequenceID ?? id`), so an update replaces the earlier one.
  public let identifier: String
  public let threadID: String
  public let title: String
  public let subtitle: String
  public let body: String
  public let sound: String?
  public let interruption: InterruptionLevel
  public let relevance: Double
  public let dismissAfter: Duration?
  public let clickURL: URL?
  public let imageURL: URL?
  public let buttons: [NotificationButton]
  public let requiresAcknowledge: Bool
  public let messageRef: MessageRef

  public init(
    identifier: String, threadID: String, title: String, subtitle: String, body: String,
    sound: String?, interruption: InterruptionLevel, relevance: Double, dismissAfter: Duration?,
    clickURL: URL?, imageURL: URL?, buttons: [NotificationButton], requiresAcknowledge: Bool,
    messageRef: MessageRef
  ) {
    self.identifier = identifier
    self.threadID = threadID
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.sound = sound
    self.interruption = interruption
    self.relevance = relevance
    self.dismissAfter = dismissAfter
    self.clickURL = clickURL
    self.imageURL = imageURL
    self.buttons = buttons
    self.requiresAcknowledge = requiresAcknowledge
    self.messageRef = messageRef
  }

  public var bodyAction: BodyAction {
    clickURL.map(BodyAction.openURL) ?? .openHistory
  }
}
