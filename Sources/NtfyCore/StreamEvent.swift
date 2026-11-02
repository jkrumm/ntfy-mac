/// One event of an ntfy subscription (docs.ntfy.sh/subscribe/api, "JSON message format").
public enum StreamEvent: Sendable, Hashable {
  /// The server accepted the subscription.
  case open
  case keepalive
  /// Sent on web-push subscriptions; carries no message.
  case pollRequest
  case message(NtfyMessage)
  /// The publisher withdrew the notification with this sequence id.
  case messageDelete(topic: String, sequenceID: String)
  /// The publisher marked the notification with this sequence id as read.
  case messageClear(topic: String, sequenceID: String)
}
