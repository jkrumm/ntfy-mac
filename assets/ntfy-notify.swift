import AppKit
import Foundation
import UserNotifications

// ─── Payload ─────────────────────────────────────────────────────────────────

struct PayloadAction: Codable {
  var identifier: String
  var title: String
  var url: String?
  var httpUrl: String?
  var httpMethod: String?
  var httpHeaders: [String: String]?
  var httpBody: String?
  var destructive: Bool?
}

struct Payload: Decodable {
  var title: String
  var subtitle: String?
  var body: String
  var sound: String?              // "Pop", "Ping", "Sosumi", etc. — nil = no sound
  var threadId: String?           // groups notifications in Notification Center
  var interruptionLevel: String?  // "passive" | "active" | "time-sensitive"
  var relevanceScore: Double?     // 0.0–1.0: sort order within a thread
  var clickUrl: String?           // opened when user clicks the notification body
  var imageUrl: String?           // remote image URL, downloaded and attached inline
  var actions: [PayloadAction]?   // action buttons (view/http)
  var categoryId: String?         // links notification to its UNNotificationCategory
}

// ─── App delegate ─────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

  func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.accessory)  // no Dock icon, no menu bar

    let center = UNUserNotificationCenter.current()
    center.delegate = self

    // Read stdin on a background thread so we don't block the main run loop
    DispatchQueue.global().async {
      let data = FileHandle.standardInput.readDataToEndOfFile()

      // Empty stdin → re-launched from a notification interaction.
      // Wait for the delegate callback to fire (didReceive response).
      if data.isEmpty { return }

      let payload: Payload
      do {
        payload = try JSONDecoder().decode(Payload.self, from: data)
      } catch {
        fputs("ntfy-notify: invalid payload: \(error)\n", stderr)
        exit(1)
      }

      center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        guard granted else {
          center.getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {
              fputs(
                "ntfy-notify: notifications denied — enable in System Settings → Notifications → ntfy-mac\n",
                stderr)
            } else if let error {
              fputs("ntfy-notify: permission error: \(error)\n", stderr)
            }
            exit(0)
          }
          return
        }

        // Register action category before posting, so the system knows the buttons
        if let actions = payload.actions, !actions.isEmpty {
          let unActions = actions.map { a -> UNNotificationAction in
            var opts: UNNotificationActionOptions = a.url != nil ? [.foreground] : []
            if a.destructive == true { opts.insert(.destructive) }
            return UNNotificationAction(identifier: a.identifier, title: a.title, options: opts)
          }
          let categoryId = payload.categoryId ?? "ntfy-default"
          let category = UNNotificationCategory(
            identifier: categoryId,
            actions: unActions,
            intentIdentifiers: [],
            options: []
          )
          center.setNotificationCategories([category])
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        if let subtitle = payload.subtitle { content.subtitle = subtitle }
        content.body = payload.body

        if let soundName = payload.sound {
          content.sound = UNNotificationSound(
            named: UNNotificationSoundName(rawValue: soundName))
        }

        if let threadId = payload.threadId {
          content.threadIdentifier = threadId
        }

        if #available(macOS 12.0, *) {
          switch payload.interruptionLevel {
          case "passive": content.interruptionLevel = .passive
          case "time-sensitive": content.interruptionLevel = .timeSensitive
          case "active": content.interruptionLevel = .active
          default: break
          }
          if let score = payload.relevanceScore {
            content.relevanceScore = score
          }
        }

        if let categoryId = payload.categoryId, payload.actions?.isEmpty == false {
          content.categoryIdentifier = categoryId
        }

        // Store click URL and actions in userInfo for re-launch handling
        var userInfo: [String: Any] = [:]
        if let url = payload.clickUrl { userInfo["clickUrl"] = url }
        if let actions = payload.actions,
           let json = try? JSONEncoder().encode(actions) {
          userInfo["actions"] = String(data: json, encoding: .utf8)
        }
        if !userInfo.isEmpty { content.userInfo = userInfo }

        // Download and attach image synchronously before posting
        if let urlString = payload.imageUrl,
           let url = URL(string: urlString),
           let imageData = try? Data(contentsOf: url) {
          let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
          let tmpUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
          if (try? imageData.write(to: tmpUrl)) != nil,
             let attachment = try? UNNotificationAttachment(identifier: "image", url: tmpUrl) {
            content.attachments = [attachment]
          }
        }

        let request = UNNotificationRequest(
          identifier: UUID().uuidString,
          content: content,
          trigger: nil
        )

        center.add(request) { _ in
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
          }
        }
      }
    }
  }

  func userNotificationCenter(
    _: UNUserNotificationCenter,
    willPresent _: UNNotification,
    withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    handler([.banner, .sound, .badge])
  }

  // Called when the user interacts with a notification (click or action button).
  // This fires when the app is re-launched with empty stdin.
  func userNotificationCenter(
    _: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo

    switch response.actionIdentifier {
    case UNNotificationDefaultActionIdentifier:
      // User clicked the notification body — open clickUrl
      if let urlStr = userInfo["clickUrl"] as? String, let url = URL(string: urlStr) {
        NSWorkspace.shared.open(url)
      }
    default:
      // User tapped an action button — find and execute it
      if let actionsStr = userInfo["actions"] as? String,
         let actionsData = actionsStr.data(using: .utf8),
         let actions = try? JSONDecoder().decode([PayloadAction].self, from: actionsData),
         let action = actions.first(where: { $0.identifier == response.actionIdentifier }) {
        if let urlStr = action.url, let url = URL(string: urlStr) {
          NSWorkspace.shared.open(url)
        } else if let httpUrlStr = action.httpUrl {
          fireHttpAction(
            urlStr: httpUrlStr,
            method: action.httpMethod ?? "POST",
            headers: action.httpHeaders,
            body: action.httpBody
          )
        }
      }
    }

    completionHandler()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
  }
}

// ─── HTTP action helper ───────────────────────────────────────────────────────

func fireHttpAction(urlStr: String, method: String, headers: [String: String]?, body: String?) {
  guard let url = URL(string: urlStr) else { return }
  var req = URLRequest(url: url)
  req.httpMethod = method
  headers?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
  if let body { req.httpBody = body.data(using: .utf8) }
  let sem = DispatchSemaphore(value: 0)
  URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
  sem.wait()
}

// ─── Entry point ──────────────────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
