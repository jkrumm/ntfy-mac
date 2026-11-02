import Foundation

/// The single pure step from a stored message to what the user is shown.
public enum DeliveryPolicy {
  /// macOS shows at most this many buttons.
  public static let maxButtons = 3

  public static func content(for message: NtfyMessage, config: Config) -> NotificationContent {
    let profile = PriorityProfile(priority: message.priority.rawValue, config: config)
    let requiresAcknowledge =
      config.reAlert && message.priority.rawValue >= config.reAlertMinPriority
    let emojis = TagEmoji.render(message.tags)
    let ref = MessageRef(topic: message.topic, id: message.id)
    return NotificationContent(
      identifier: message.notificationIdentifier,
      threadID: message.topic,
      title: message.title ?? capitalized(message.topic),
      subtitle: emojis.isEmpty ? message.topic : "\(message.topic) • \(emojis)",
      body: message.body,
      sound: profile.sound,
      interruption: profile.interruption,
      relevance: profile.relevance,
      dismissAfter: profile.dismissAfter,
      clickURL: message.click.flatMap(URLPolicy.openable),
      imageURL: imageURL(for: message),
      buttons: buttons(for: message, config: config, requiresAcknowledge: requiresAcknowledge),
      requiresAcknowledge: requiresAcknowledge,
      messageRef: ref)
  }

  private static func capitalized(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
  }

  /// An image attachment wins over the icon; a URL that fails the policy is skipped.
  private static func imageURL(for message: NtfyMessage) -> URL? {
    let attachment = message.attachment.flatMap { $0.isImage ? $0.url : nil }
    return [attachment, message.icon].compactMap { $0 }.lazy.compactMap(URLPolicy.imageURL).first
  }

  private static func buttons(
    for message: NtfyMessage, config: Config, requiresAcknowledge: Bool
  ) -> [NotificationButton] {
    var result: [NotificationButton] = []
    if requiresAcknowledge {
      result.append(
        NotificationButton(id: "acknowledge", title: "Acknowledge", action: .acknowledge))
    }
    var usedIDs: Set<String> = Set(result.map(\.id))
    for action in message.actions where result.count < maxButtons {
      guard let button = button(for: action, config: config, usedIDs: &usedIDs) else { continue }
      result.append(button)
    }
    return result
  }

  private static func button(
    for action: MessageAction, config: Config, usedIDs: inout Set<String>
  ) -> NotificationButton? {
    guard action.kind == .view || action.kind == .http, let url = action.url else { return nil }
    let decision = ActionPolicy.evaluate(action, config: config)
    if case .deny = decision { return nil }
    let id = uniqueID(for: action, usedIDs: &usedIDs)
    guard action.kind == .http else {
      return NotificationButton(id: id, title: action.label, action: .openURL(url))
    }
    var confirmation: String?
    if case .confirm(let reason) = decision { confirmation = reason }
    let call = HTTPCall(
      url: url, method: action.method ?? "POST", headers: action.headers, body: action.body)
    return NotificationButton(
      id: id, title: action.label, action: .http(call, confirmation: confirmation))
  }

  /// `kind-label` with whitespace folded to `-`, then `-1`, `-2`... on collisions (the 1.x scheme).
  private static func uniqueID(for action: MessageAction, usedIDs: inout Set<String>) -> String {
    let label = action.label.lowercased().replacing(/\s+/, with: "-")
    let base = "\(action.kind.name)-\(label)"
    var id = base
    var suffix = 1
    while usedIDs.contains(id) {
      id = "\(base)-\(suffix)"
      suffix += 1
    }
    usedIDs.insert(id)
    return id
  }
}

extension NtfyMessage {
  /// Stable per notification, so an update of a sequence replaces the notification it updates.
  var notificationIdentifier: String { "\(topic)/\(sequenceID ?? id)" }
}
