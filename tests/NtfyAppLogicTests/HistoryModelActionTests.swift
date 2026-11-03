import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct HistoryModelActionTests {
  private let alerts = MessageKey(topic: "alerts", id: "a")
  /// The export page size of `HistoryModel`.
  private let exportPage = 500

  @Test func acknowledgingAcknowledgesAndWithdrawsTheNotification() async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    await rig.model.select(alerts)
    await rig.model.acknowledge()
    #expect(rig.model.detail?.isAcknowledged == true)
    #expect(rig.model.rows.first?.isAcknowledged == true)
    #expect(await rig.pipeline.poster.removed == ["alerts/a"])
    rig.model.stop()
  }

  @Test func markUnreadReversesTheReadOnSelectAndKeepsTheAcknowledgement() async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    await rig.model.select(alerts)
    await rig.model.acknowledge()
    await rig.model.markUnread()
    #expect(rig.model.detail?.isRead == false)
    #expect(rig.model.detail?.isAcknowledged == true)
    #expect(rig.model.totalUnread == 1)
    await rig.model.markRead(alerts)
    #expect(rig.model.detail?.isRead == true)
    #expect(rig.model.totalUnread == 0)
    rig.model.stop()
  }

  @Test func markAllReadHandlesOneTopicOrEveryTopic() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 3)
    await rig.add("a2", topic: "alerts", age: 2)
    await rig.add("b1", topic: "builds", age: 1)
    await rig.start()
    await rig.model.markAllRead(topic: "alerts")
    #expect(rig.model.topics.first { $0.topic == "alerts" }?.unread == 0)
    #expect(rig.model.topics.first { $0.topic == "builds" }?.unread == 1)
    await rig.model.markAllRead(topic: nil)
    #expect(rig.model.totalUnread == 0)
    rig.model.stop()
  }

  private nonisolated static let remindCases: [(RemindChoice, TimeInterval)] = [
    (.fifteenMinutes, 900), (.oneHour, 3600), (.tomorrowMorning, 35_200),
  ]

  @Test(arguments: remindCases)
  func remindSnoozesToTheChoicesTime(_ choice: RemindChoice, _ seconds: TimeInterval) async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    await rig.model.select(alerts)
    await rig.model.remind(choice)
    let expected = rig.pipeline.clock.now().addingTimeInterval(seconds)
    #expect(await rig.pipeline.history.message(topic: "alerts", id: "a")?.remindAt == expected)
    #expect(rig.model.detail?.remindAt == expected)
    rig.model.stop()
  }

  @Test func remindingAnUnknownMessageChangesNothing() async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    await rig.model.remind(.oneHour, MessageKey(topic: "alerts", id: "ghost"))
    let later = rig.pipeline.clock.now().addingTimeInterval(10 * 86_400)
    #expect(await rig.pipeline.history.dueReminders(now: later).isEmpty)
    rig.model.stop()
  }

  @Test func actionsOnNothingDoNothing() async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    await rig.model.acknowledge()
    await rig.model.markRead()
    await rig.model.markUnread()
    await rig.model.remind(.oneHour)
    await rig.model.delete()
    #expect(rig.model.totalUnread == 1)
    #expect(rig.ids() == ["a"])
    #expect(await rig.pipeline.poster.removed.isEmpty)
    rig.model.stop()
  }

  @Test func deleteRemovesTheMessageItsNotificationAndTheSelection() async {
    let rig = HistoryModelRig()
    await rig.add("a", age: 2)
    await rig.add("b", age: 1)
    await rig.pipeline.delivery.deliver(rig.pipeline.message("a", age: 2))
    await rig.start()
    await rig.model.select(alerts)
    await rig.model.delete()
    #expect(rig.model.selection == nil && rig.model.detail == nil)
    #expect(rig.ids() == ["b"])
    #expect(rig.model.resultCount == 1)
    #expect(await rig.pipeline.poster.removed.contains("alerts/a"))
    rig.model.stop()
  }

  @Test func deleteByKeyKeepsAnotherSelection() async {
    let rig = HistoryModelRig()
    await rig.add("a", age: 2)
    await rig.add("b", age: 1)
    await rig.start()
    await rig.model.select(alerts)
    await rig.model.delete(MessageKey(topic: "alerts", id: "b"))
    #expect(rig.model.selection == alerts)
    #expect(rig.ids() == ["a"])
    rig.model.stop()
  }

  @Test func deleteAllEmptiesTheTopicAndLeavesTheOthers() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 3)
    await rig.add("a2", topic: "alerts", age: 2)
    await rig.add("b1", topic: "builds", age: 1)
    await rig.start()
    rig.model.selectedTopic = "alerts"
    await rig.model.select(alerts.withID("a1"))
    await rig.model.deleteAll(topic: "alerts")
    #expect(rig.model.selection == nil)
    #expect(rig.model.selectedTopic == nil)
    #expect(rig.model.topics.map(\.topic) == ["builds"])
    #expect(await rig.pipeline.poster.removed.sorted() == ["alerts/a1", "alerts/a2"])
    await rig.model.refresh()
    #expect(rig.ids() == ["b1"])
    rig.model.stop()
  }

  @Test func exportCoversEverythingTheFiltersMatchNotJustThePage() async throws {
    let rig = HistoryModelRig(pageSize: 1)
    await rig.add("a1", topic: "alerts", age: 3, title: "=evil")
    await rig.add("a2", topic: "alerts", age: 2)
    await rig.add("b1", topic: "builds", age: 1)
    await rig.start()
    #expect(rig.ids().count == 1)
    let all = try #require(try await rig.model.export(.json))
    let objects = try #require(try JSONSerialization.jsonObject(with: all.data) as? [[String: Any]])
    #expect(objects.compactMap { $0["id"] as? String } == ["b1", "a2", "a1"])
    #expect(all.suggestedFileName == "ntfy-all-20231114T221320Z.json")
    rig.model.selectedTopic = "alerts"
    await rig.model.refresh()
    let csv = try #require(try await rig.model.export(.csv))
    let text = String(bytes: csv.data, encoding: .utf8) ?? ""
    #expect(text.contains("'=evil"))
    #expect(!text.contains("builds"))
    #expect(csv.suggestedFileName == "ntfy-alerts-20231114T221320Z.csv")
    rig.model.unreadOnly = true
    rig.model.minPriority = .max
    await rig.model.refresh()
    #expect(try await rig.model.export(.json) == nil)
    rig.model.stop()
  }

  /// 501 messages: one full export page and a second page of one.
  private func exportRig() async -> HistoryModelRig {
    let rig = HistoryModelRig()
    for index in 0..<(exportPage + 1) {
      await rig.add("m\(index)", age: 1000 - Double(index))
    }
    await rig.start()
    return rig
  }

  private func exportedIDs(_ export: HistoryExport?) throws -> [String] {
    let data = try #require(export).data
    let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    return objects.compactMap { $0["id"] as? String }
  }

  @Test func aMessageArrivingMidExportIsLeftOutAndNothingRepeats() async throws {
    let rig = await exportRig()
    let (history, clock) = (rig.pipeline.history, rig.pipeline.clock)
    await history.setAfterEntries { query in
      guard query.offset == 0 else { return }
      clock.advance(by: .seconds(5))
      let late = NtfyMessage(id: "late", topic: "alerts", time: clock.now(), body: "late")
      _ = try? await history.append(late)
    }
    let ids = try exportedIDs(try await rig.model.export(.json))
    #expect(ids.count == exportPage + 1)
    #expect(Set(ids).count == ids.count)
    #expect(!ids.contains("late"))
    rig.model.stop()
  }

  @Test func aMessageWithinTheBoundIsDeduplicatedWhenPagingShifts() async throws {
    let rig = await exportRig()
    let (history, clock) = (rig.pipeline.history, rig.pipeline.clock)
    await history.setAfterEntries { query in
      guard query.offset == 0 else { return }
      let early = NtfyMessage(id: "early", topic: "alerts", time: clock.now(), body: "early")
      _ = try? await history.append(early)
    }
    let ids = try exportedIDs(try await rig.model.export(.json))
    #expect(Set(ids).count == ids.count)
    #expect(ids.filter { $0 == "early" }.count <= 1)
    rig.model.stop()
  }
}

extension MessageKey {
  fileprivate func withID(_ id: String) -> MessageKey { MessageKey(topic: topic, id: id) }
}

@MainActor @Suite struct HistoryModelAttachmentTests {
  private let file = MessageAttachment(
    url: URL(string: "https://e.com/report.pdf")!, name: "report.pdf", mimeType: "application/pdf",
    size: 10)
  private let key = MessageKey(topic: "alerts", id: "a")
  private let local = URL(fileURLWithPath: "/tmp/cache/report.pdf")

  private func rig(attachment: MessageAttachment?) async -> HistoryModelRig {
    let rig = HistoryModelRig()
    await rig.add("a", attachment: attachment)
    await rig.add("plain", age: 1)
    await rig.start()
    return rig
  }

  @Test func theStateGoesFromIdleThroughLoadingToReady() async {
    let rig = await rig(attachment: file)
    await rig.pipeline.attachments.set(file: local)
    await rig.pipeline.attachments.hold()
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    #expect(rig.model.attachmentState(for: key) == .idle)
    rig.model.loadAttachment(for: key)
    #expect(rig.model.attachmentState(for: key) == .loading)
    await rig.pipeline.attachments.release()
    #expect(await rig.eventually { rig.model.attachmentState(for: key) == .ready(local) })
    #expect(await rig.pipeline.attachments.requested == [file])
    rig.model.stop()
  }

  @Test func aFailureBecomesAMessage() async {
    let rig = await rig(attachment: file)
    await rig.pipeline.attachments.set(failure: .serverUnreachable)
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    rig.model.loadAttachment(for: key)
    #expect(
      await rig.eventually {
        rig.model.attachmentState(for: key) == .failed("The server could not be reached.")
      })
    rig.model.stop()
  }

  @Test func loadingTwiceAtOnceFetchesOnce() async {
    let rig = await rig(attachment: file)
    await rig.pipeline.attachments.hold()
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    rig.model.loadAttachment(for: key)
    rig.model.loadAttachment(for: key)
    await rig.pipeline.attachments.release()
    #expect(await rig.eventually { rig.model.attachmentState(for: key) != .loading })
    #expect(await rig.pipeline.attachments.requested.count == 1)
    rig.model.stop()
  }

  @Test func cancelReturnsToIdleAndAnAbandonedResultIsIgnored() async {
    let rig = await rig(attachment: file)
    await rig.pipeline.attachments.hold()
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    rig.model.loadAttachment(for: key)
    rig.model.cancelAttachment(for: key)
    #expect(rig.model.attachmentState(for: key) == .idle)
    await rig.pipeline.attachments.release()
    for _ in 0..<2000 { await Task.yield() }
    #expect(rig.model.attachmentState(for: key) == .idle)
    rig.model.stop()
  }

  @Test func aRunningDownloadSurvivesSelectingAnotherMessage() async {
    let rig = await rig(attachment: file)
    await rig.pipeline.attachments.set(file: local)
    await rig.pipeline.attachments.hold()
    rig.model.loadAttachment(for: key)
    await rig.model.select(MessageKey(topic: "alerts", id: "plain"))
    #expect(rig.model.attachmentState(for: key) == .loading)
    await rig.pipeline.attachments.release()
    #expect(await rig.eventually { rig.model.attachmentState(for: key) == .ready(local) })
    rig.model.stop()
  }

  @Test func twoMessagesLoadTheirAttachmentsIndependently() async {
    let rig = HistoryModelRig()
    await rig.add("a", attachment: file)
    await rig.add("b", age: 1, attachment: file)
    await rig.start()
    await rig.pipeline.attachments.set(file: local)
    let other = MessageKey(topic: "alerts", id: "b")
    rig.model.loadAttachment(for: key)
    #expect(rig.model.attachmentState(for: other) == .idle)
    #expect(await rig.eventually { rig.model.attachmentState(for: key) == .ready(local) })
    #expect(rig.model.attachmentState(for: other) == .idle)
    rig.model.stop()
  }

  @Test func aMessageWithoutAnAttachmentDoesNothing() async {
    let rig = await rig(attachment: nil)
    await rig.model.select(MessageKey(topic: "alerts", id: "plain"))
    rig.model.loadAttachment(for: key)
    #expect(rig.model.attachmentState(for: key) == .idle)
    #expect(await rig.pipeline.attachments.requested.isEmpty)
    rig.model.stop()
  }

  @Test func anExpiredAttachmentFailsWithoutARequest() async {
    var expired = file
    expired = MessageAttachment(
      url: file.url, name: file.name, mimeType: file.mimeType, size: file.size,
      expires: Date(timeIntervalSince1970: 1))
    let rig = await rig(attachment: expired)
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    #expect(rig.model.detail?.attachment?.isExpired == true)
    rig.model.loadAttachment(for: key)
    #expect(
      rig.model.attachmentState(for: key) == .failed("The server no longer has this attachment."))
    #expect(await rig.pipeline.attachments.requested.isEmpty)
    rig.model.stop()
  }
}

@Suite struct HistoryChoicesTests {
  private func date(_ text: String) -> Date {
    Date(timeIntervalSince1970: TimeInterval(text) ?? 0)
  }

  private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, in calendar: Calendar) -> Date
  {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .now
  }

  @Test func tomorrowMorningIsTheNextDaysEightEvenInTheSmallHours() {
    let utc = HistoryModelRig.utc
    for hour in [0, 3, 7, 8, 9, 23] {
      let now = at(2030, 5, 10, hour, in: utc)
      #expect(
        RemindChoice.tomorrowMorning.time(from: now, calendar: utc) == at(2030, 5, 11, 8, in: utc),
        "hour \(hour)")
    }
  }

  @Test func tomorrowMorningUsesTheCalendarsTimeZoneAndSurvivesTheMonthEnd() {
    var berlin = Calendar(identifier: .gregorian)
    berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    let now = at(2030, 1, 31, 23, in: berlin)
    #expect(
      RemindChoice.tomorrowMorning.time(from: now, calendar: berlin)
        == at(2030, 2, 1, 8, in: berlin))
    // The clocks change on 2030-03-31: 08:00 local is then one hour earlier in UTC.
    let before = at(2030, 3, 30, 12, in: berlin)
    let morning = RemindChoice.tomorrowMorning.time(from: before, calendar: berlin)
    #expect(morning == at(2030, 3, 31, 8, in: berlin))
  }

  @Test func shortDelaysAreRelativeToNow() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(RemindChoice.fifteenMinutes.time(from: now, calendar: .current) == now + 900)
    #expect(RemindChoice.oneHour.time(from: now, calendar: .current) == now + 3600)
  }

  @Test func dateFiltersStartWhereTheyShould() {
    let utc = HistoryModelRig.utc
    let now = at(2030, 5, 10, 15, in: utc)
    #expect(HistoryDateFilter.all.start(from: now, calendar: utc) == nil)
    #expect(HistoryDateFilter.today.start(from: now, calendar: utc) == at(2030, 5, 10, 0, in: utc))
    #expect(HistoryDateFilter.week.start(from: now, calendar: utc) == now - 7 * 86_400)
    #expect(HistoryDateFilter.month.start(from: now, calendar: utc) == now - 30 * 86_400)
    #expect(HistoryDateFilter.allCases.count == 4)
  }
}
