#if SNAPSHOT_HARNESS
  import Foundation
  import NtfyCore

  /// Realistic messages for the snapshots, spread over several days and topics. Times are
  /// relative to `now`, so the day headers and relative times read as they would in use.
  enum SnapshotFixtures {
    static let longTopic = "kubernetes-production-cluster-deployments-eu-west"
    static let chartURL = URL(string: "https://ntfy.example.com/file/disk-usage.png")!

    struct Entry {
      let message: NtfyMessage
      let isRead: Bool
      let isAcknowledged: Bool
    }

    private static let markdown = """
      ## Weekly summary

      - **3** doors opened after midnight
      - Heating ran for `4h 12m`
      - Next check: [dashboard](https://home.example.com/summary)

      > Everything looks normal.
      """

    static func entries(now: Date) -> [Entry] {
      alerts(now: now) + ci(now: now) + home(now: now) + kubernetes(now: now)
    }

    /// The minutes before `now`, as a date.
    private static func ago(_ minutes: Double, from now: Date) -> Date {
      now.addingTimeInterval(-minutes * 60)
    }

    private static let hour = 60.0
    private static let day = 24 * hour

    /// The urgent one, unacknowledged, with actions and an image, and older acknowledged ones.
    private static func alerts(now: Date) -> [Entry] {
      func at(_ minutes: Double) -> Date { ago(minutes, from: now) }
      return [
        Entry(
          message: NtfyMessage(
            id: "al-1", topic: "alerts", time: at(4), title: "Disk almost full on nas-01",
            body: "Volume /mnt/tank is at 96% (4.1 TB of 4.3 TB). Snapshots older than 30 days "
              + "can be pruned.\nFree space drops about 12 GB per hour.",
            priority: .max, tags: ["rotating_light", "warning"],
            click: URL(string: "https://nas.example.com/volumes"),
            attachment: MessageAttachment(
              url: chartURL, name: "disk-usage.png", mimeType: "image/png", size: 48_213),
            actions: [
              MessageAction(
                kind: .view, label: "Open dashboard", url: URL(string: "https://nas.example.com")),
              MessageAction(
                kind: .http, label: "Prune snapshots",
                url: URL(string: "https://nas.example.com/api/prune")),
            ]),
          isRead: false, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "al-2", topic: "alerts", time: at(25), title: "Backup job failed",
            body: "restic exited with code 1: repository is locked by another process.",
            priority: .high, tags: ["x"]),
          isRead: false, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "al-3", topic: "alerts", time: at(day + 2 * hour),
            title: "Certificate expires in 7 days",
            body: "home.example.com renews automatically; no action needed unless it fails again.",
            priority: .high, tags: ["lock"]),
          isRead: true, isAcknowledged: true),
        Entry(
          message: NtfyMessage(
            id: "al-4", topic: "alerts", time: at(3 * day), title: "UPS on battery",
            body: "Power returned after 42 seconds.", priority: .max, tags: ["zap"]),
          isRead: true, isAcknowledged: true),
      ]
    }

    /// Normal, low and min with emoji tags.
    private static func ci(now: Date) -> [Entry] {
      func at(_ minutes: Double) -> Date { ago(minutes, from: now) }
      return [
        Entry(
          message: NtfyMessage(
            id: "ci-1", topic: "ci", time: at(11), title: "Build #4812 passed",
            body: "main · 214 tests · 3m 12s", priority: .default,
            tags: ["white_check_mark"], click: URL(string: "https://ci.example.com/runs/4812")),
          isRead: false, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "ci-2", topic: "ci", time: at(95), title: "Deploy to staging finished",
            body: "api@4f2c1ab is live on staging.example.com", priority: .default,
            tags: ["rocket"]),
          isRead: true, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "ci-3", topic: "ci", time: at(day + 5 * hour), title: "Nightly cache warm-up",
            body: "Finished in 18 minutes.", priority: .low, tags: ["hourglass"]),
          isRead: true, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "ci-4", topic: "ci", time: at(day + 6 * hour), body: "runner-3 heartbeat",
            priority: .min),
          isRead: true, isAcknowledged: false),
      ]
    }

    /// Normal, markdown and a very long title and body.
    private static func home(now: Date) -> [Entry] {
      func at(_ minutes: Double) -> Date { ago(minutes, from: now) }
      return [
        Entry(
          message: NtfyMessage(
            id: "ho-1", topic: "home", time: at(38), title: "Front door opened",
            body: "Opened at 09:14.", priority: .default, tags: ["door"]),
          isRead: false, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "ho-2", topic: "home", time: at(day + 90), title: "Washing machine done",
            body: "Cycle finished. Clothes are waiting.", priority: .low, tags: ["tada"]),
          isRead: true, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "ho-3", topic: "home", time: at(2 * day + hour), title: "Weekly home summary",
            body: markdown, priority: .default, tags: ["house"], contentType: "text/markdown"),
          isRead: true, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "ho-4", topic: "home", time: at(12 * day),
            title:
              "A rather long notification title that goes on for quite a while to see how it wraps",
            body:
              "The body is long as well. It describes in detail what happened, because some senders "
              + "put whole log excerpts into a notification, and the layout has to stay readable "
              + "when that happens. It keeps going for several lines on purpose.",
            priority: .default, tags: ["memo"]),
          isRead: true, isAcknowledged: false),
      ]
    }

    /// A topic with a very long name.
    private static func kubernetes(now: Date) -> [Entry] {
      func at(_ minutes: Double) -> Date { ago(minutes, from: now) }
      return [
        Entry(
          message: NtfyMessage(
            id: "k8-1", topic: longTopic, time: at(160), title: "Rollout complete",
            body: "payments-api 14/14 pods ready.", priority: .default, tags: ["ship"]),
          isRead: false, isAcknowledged: false),
        Entry(
          message: NtfyMessage(
            id: "k8-2", topic: longTopic, time: at(day + 40), title: "Autoscaler added 2 nodes",
            body: "Pending pods: 0", priority: .min),
          isRead: true, isAcknowledged: false),
      ]
    }
  }
#endif
