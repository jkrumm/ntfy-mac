import Foundation
import NtfyCore
import NtfyIPC

/// Checks a `notify` request on the app's side. Any process of the same user can write to the
/// socket, so the CLI's own validation is a courtesy, never the guard.
enum NotifyValidation {
  static let maxTitle = 256
  static let maxBody = 4096
  static let maxTags = 16
  static let maxTag = 64
  static let maxDismissSeconds: TimeInterval = 86_400

  struct Rejection: Error {
    let message: String
  }

  /// The payload's values that need cleaning up, or the reason it is refused.
  struct Accepted {
    let title: String?
    let dismissAfter: TimeInterval?
  }

  static func check(_ payload: NotifyPayload) -> Result<Accepted, Rejection> {
    if payload.body.isEmpty { return refuse("notify needs a non-empty body") }
    if payload.body.count > maxBody { return refuse("body is longer than \(maxBody) characters") }
    if (payload.title?.count ?? 0) > maxTitle {
      return refuse("title is longer than \(maxTitle) characters")
    }
    if payload.tags.count > maxTags { return refuse("more than \(maxTags) tags") }
    if payload.tags.contains(where: { $0.count > maxTag }) {
      return refuse("a tag is longer than \(maxTag) characters")
    }
    if let url = payload.clickURL, URLPolicy.openable(url) == nil {
      return refuse("the click URL must be http, https or mailto")
    }
    if let seconds = payload.dismissAfterSeconds, !seconds.isFinite {
      return refuse("the dismiss time must be a number of seconds")
    }
    let dismiss = payload.dismissAfterSeconds.map { min(max($0, 0), maxDismissSeconds) }
    let title = payload.title.flatMap { $0.isEmpty ? nil : $0 }
    return .success(Accepted(title: title, dismissAfter: dismiss))
  }

  private static func refuse(_ message: String) -> Result<Accepted, Rejection> {
    .failure(Rejection(message: message))
  }
}
