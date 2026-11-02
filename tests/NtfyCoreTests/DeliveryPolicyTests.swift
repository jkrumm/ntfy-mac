import Foundation
import Testing

@testable import NtfyCore

@Suite struct DeliveryPolicyTests {
  private static let time = Date(timeIntervalSince1970: 1_700_000_000)

  private func message(
    id: String = "abc12345", topic: String = "alerts", title: String? = nil,
    priority: Priority = .default, tags: [String] = [], click: URL? = nil,
    sequenceID: String? = nil, icon: URL? = nil, attachment: MessageAttachment? = nil,
    actions: [MessageAction] = []
  ) -> NtfyMessage {
    NtfyMessage(
      id: id, topic: topic, time: Self.time, title: title, body: "body text",
      priority: priority, tags: tags, click: click, sequenceID: sequenceID, icon: icon,
      attachment: attachment, actions: actions)
  }

  private func content(_ message: NtfyMessage, _ config: Config = Config()) -> NotificationContent {
    DeliveryPolicy.content(for: message, config: config)
  }

  private func view(_ label: String, _ url: String = "https://example.com") -> MessageAction {
    MessageAction(kind: .view, label: label, url: URL(string: url))
  }

  // MARK: text

  @Test func titleFallsBackToCapitalisedTopic() {
    #expect(content(message()).title == "Alerts")
    #expect(content(message(title: "Custom Title")).title == "Custom Title")
    #expect(content(message(topic: "")).title.isEmpty)
  }

  @Test func subtitleIsTheTopicOrTopicAndEmojis() {
    #expect(content(message()).subtitle == "alerts")
    #expect(content(message(tags: ["fire", "warning"])).subtitle == "alerts • 🔥 ⚠️")
    #expect(content(message(tags: ["custom"])).subtitle == "alerts • custom")
  }

  @Test func bodyAndThread() {
    let result = content(message())
    #expect(result.body == "body text")
    #expect(result.threadID == "alerts")
    #expect(result.messageRef == MessageRef(topic: "alerts", id: "abc12345"))
  }

  @Test func identifierIsNamespacedAndUsesTheSequence() {
    #expect(content(message()).identifier == "alerts/abc12345")
    #expect(content(message(sequenceID: "job-7")).identifier == "alerts/job-7")
    #expect(content(message(topic: "other", sequenceID: "job-7")).identifier == "other/job-7")
  }

  // MARK: priority

  @Test func defaultPriorityProfile() {
    let result = content(message())
    #expect(result.sound == "Pop")
    #expect(result.interruption == .active)
    #expect(result.relevance == 0.5)
    #expect(result.dismissAfter == .seconds(8))
  }

  @Test func urgentPriorityNeverDismisses() {
    let result = content(message(priority: .max))
    #expect(result.sound == "Ping")
    #expect(result.interruption == .timeSensitive)
    #expect(result.relevance == 1.0)
    #expect(result.dismissAfter == nil)
  }

  @Test func overridesApply() {
    let config = Config(sounds: [3: .silent, 5: .named("Glass")], dismiss: [3: 0])
    #expect(content(message(), config).sound == nil)
    #expect(content(message(), config).dismissAfter == nil)
    let urgent = content(message(priority: .max), config)
    #expect(urgent.sound == "Glass")
    #expect(urgent.interruption == .timeSensitive)
  }

  // MARK: click and image

  @Test func clickURLIsValidatedAndDrivesTheBodyAction() throws {
    let web = try #require(URL(string: "https://example.com/x"))
    #expect(content(message(click: web)).clickURL == web)
    #expect(content(message(click: web)).bodyAction == .openURL(web))
    #expect(content(message()).bodyAction == .openHistory)
    let bad = try #require(URL(string: "javascript:alert(1)"))
    #expect(content(message(click: bad)).clickURL == nil)
    #expect(content(message(click: bad)).bodyAction == .openHistory)
  }

  @Test func imageAttachmentWinsOverTheIcon() throws {
    let result = content(
      message(
        icon: URL(string: "https://example.com/icon.png"),
        attachment: MessageAttachment(
          url: try #require(URL(string: "https://example.com/img.png")), mimeType: "image/png")))
    #expect(result.imageURL == URL(string: "https://example.com/img.png"))
  }

  @Test func iconIsTheFallback() throws {
    let icon = URL(string: "https://example.com/icon.png")
    let pdf = MessageAttachment(
      url: try #require(URL(string: "https://example.com/f.pdf")), mimeType: "application/pdf")
    let untyped = MessageAttachment(url: try #require(URL(string: "https://example.com/i.png")))
    #expect(content(message(icon: icon, attachment: pdf)).imageURL == icon)
    #expect(content(message(icon: icon, attachment: untyped)).imageURL == icon)
    #expect(content(message(icon: icon)).imageURL == icon)
    #expect(content(message()).imageURL == nil)
    #expect(content(message(attachment: untyped)).imageURL == nil)
  }

  @Test func imagesMustBeWebURLs() throws {
    let file = MessageAttachment(
      url: try #require(URL(string: "file:///tmp/a.png")), mimeType: "image/png")
    let icon = URL(string: "https://example.com/icon.png")
    #expect(content(message(icon: icon, attachment: file)).imageURL == icon)
    #expect(content(message(attachment: file)).imageURL == nil)
  }

  // MARK: buttons

  @Test func noDefaultButtons() {
    #expect(content(message()).buttons.isEmpty)
    #expect(content(message(priority: .high)).buttons.isEmpty)
  }

  @Test func viewActionBecomesAButton() {
    let button = content(message(actions: [view("Open Link")])).buttons
    #expect(button.count == 1)
    #expect(button[0].id == "view-open-link")
    #expect(button[0].title == "Open Link")
    #expect(button[0].action == .openURL(URL(string: "https://example.com")!))
  }

  @Test func httpActionCarriesItsRequest() throws {
    let action = MessageAction(
      kind: .http, label: "Ack", url: URL(string: "https://api.example.com/ack"), method: "PUT",
      headers: ["X-Token": "abc"], body: #"{"ok":true}"#)
    let button = try #require(content(message(actions: [action])).buttons.first)
    let call = HTTPCall(
      url: try #require(URL(string: "https://api.example.com/ack")), method: "PUT",
      headers: ["X-Token": "abc"], body: #"{"ok":true}"#)
    #expect(button.id == "http-ack")
    #expect(button.action == .http(call, confirmation: nil))
  }

  @Test func httpMethodDefaultsToPost() throws {
    let action = MessageAction(kind: .http, label: "Fire", url: URL(string: "https://e.com/hook"))
    let button = try #require(content(message(actions: [action])).buttons.first)
    guard case .http(let call, _) = button.action else {
      Issue.record("expected http")
      return
    }
    #expect(call.method == "POST")
  }

  @Test func privateHTTPTargetsNeedConfirmationUnlessOptedIn() throws {
    let action = MessageAction(kind: .http, label: "Hit", url: URL(string: "http://192.168.1.2/x"))
    let guarded = try #require(content(message(actions: [action])).buttons.first)
    guard case .http(_, let confirmation) = guarded.action else {
      Issue.record("expected http")
      return
    }
    #expect(confirmation != nil)
    let open = try #require(
      content(message(actions: [action]), Config(allowPrivateNetworkActions: true)).buttons.first)
    #expect(open.action == .http(try #require(httpCall(open)), confirmation: nil))
  }

  private func httpCall(_ button: NotificationButton) -> HTTPCall? {
    guard case .http(let call, _) = button.action else { return nil }
    return call
  }

  @Test func skippedKindsAndDeniedActionsProduceNoButton() {
    let actions = [
      MessageAction(kind: .broadcast, label: "Broadcast"),
      MessageAction(kind: .copy, label: "Copy"),
      MessageAction(kind: .unknown("x"), label: "X"),
      view("Bad", "javascript:alert(1)"),
      MessageAction(kind: .http, label: "NoURL"),
      view("View"),
    ]
    let buttons = content(message(actions: actions)).buttons
    #expect(buttons.map(\.title) == ["View"])
  }

  @Test func duplicateLabelsGetUniqueIDs() {
    let buttons = content(
      message(actions: [
        view("Open", "https://a.example.com"), view("Open", "https://b.example.com"),
        view("Open", "https://c.example.com"),
      ])
    ).buttons
    #expect(buttons.map(\.id) == ["view-open", "view-open-1", "view-open-2"])
  }

  @Test func whitespaceInLabelsFoldsToDashes() {
    #expect(
      content(message(actions: [view("Open  the\tDoor")])).buttons.first?.id == "view-open-the-door"
    )
  }

  // MARK: acknowledge

  @Test func urgentMessagesGetOneLeadingAcknowledgeButton() {
    let result = content(message(priority: .max, actions: [view("Open")]))
    #expect(result.requiresAcknowledge)
    #expect(result.buttons.map(\.id) == ["acknowledge", "view-open"])
    #expect(result.buttons.first?.action == .acknowledge)
  }

  @Test func acknowledgeFollowsThePriorityThresholdAndSwitch() {
    #expect(content(message(priority: .high)).requiresAcknowledge == false)
    #expect(content(message(priority: .high), Config(reAlertMinPriority: 4)).requiresAcknowledge)
    #expect(content(message(priority: .max), Config(reAlert: false)).requiresAcknowledge == false)
    #expect(content(message(priority: .max), Config(reAlert: false)).buttons.isEmpty)
    #expect(content(message(priority: .min), Config(reAlertMinPriority: 1)).requiresAcknowledge)
  }

  @Test func buttonsAreCappedAtThreeAndAcknowledgeIsKept() {
    let actions = (1...5).map { view("A\($0)", "https://e.com/\($0)") }
    #expect(content(message(actions: actions)).buttons.map(\.title) == ["A1", "A2", "A3"])
    let urgent = content(message(priority: .max, actions: actions))
    #expect(urgent.buttons.map(\.id) == ["acknowledge", "view-a1", "view-a2"])
  }
}
