import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct HistoryModelListTests {
  @Test func theSidebarListsTopicsNewestFirstWithUnreadCounts() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 30)
    await rig.add("a2", topic: "alerts", age: 20)
    await rig.add("b1", topic: "builds", age: 10)
    await rig.pipeline.history.markRead(topic: "alerts", id: "a1")
    await rig.start()
    #expect(rig.model.isAvailable)
    #expect(rig.model.topics.map(\.topic) == ["builds", "alerts"])
    #expect(rig.model.topics.map(\.unread) == [1, 1])
    #expect(rig.model.totalUnread == 2)
    #expect(rig.model.totalMessages == 3)
    #expect(rig.ids() == ["b1", "a2", "a1"])
    #expect(rig.model.resultCount == 3)
    #expect(!rig.model.hasMore)
    #expect(!rig.model.isFiltering)
    rig.model.stop()
  }

  @Test func loadingTheListMarksNothingRead() async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    #expect(rig.model.rows.allSatisfy { !$0.isRead })
    #expect(rig.model.selection == nil)
    rig.model.stop()
  }

  @Test func theTopicFilterNarrowsListAndCount() async {
    let rig = HistoryModelRig()
    await rig.add("a1", topic: "alerts", age: 3)
    await rig.add("b1", topic: "builds", age: 2)
    await rig.add("a2", topic: "alerts", age: 1)
    await rig.start()
    rig.model.selectedTopic = "alerts"
    await rig.model.refresh()
    #expect(rig.ids() == ["a2", "a1"])
    #expect(rig.model.resultCount == 2)
    #expect(rig.model.isFiltering)
    #expect(rig.model.topics.count == 2)
    rig.model.selectedTopic = nil
    await rig.model.refresh()
    #expect(rig.model.resultCount == 3)
    rig.model.stop()
  }

  @Test func theMinimumPriorityAndUnreadFiltersCombine() async {
    let rig = HistoryModelRig()
    await rig.add("low", age: 4, priority: .low)
    await rig.add("high", age: 3, priority: .high)
    await rig.add("max", age: 2, priority: .max)
    await rig.pipeline.history.markRead(topic: "alerts", id: "max")
    await rig.start()
    rig.model.minPriority = .high
    await rig.model.refresh()
    #expect(rig.ids() == ["max", "high"])
    rig.model.unreadOnly = true
    await rig.model.refresh()
    #expect(rig.ids() == ["high"])
    #expect(rig.model.resultCount == 1)
    rig.model.stop()
  }

  @Test func theDateFilterCountsFromMidnightOrBackFromNow() async {
    let rig = HistoryModelRig()
    let day: TimeInterval = 24 * 60 * 60
    // The clock starts at 22:13 UTC, so 23 hours ago is yesterday.
    await rig.add("now", age: 60)
    await rig.add("yesterday", age: 23 * 60 * 60)
    await rig.add("fiveDays", age: 5 * day)
    await rig.add("twentyDays", age: 20 * day)
    await rig.add("fortyDays", age: 40 * day)
    await rig.start()
    func shown(_ filter: HistoryDateFilter) async -> [String] {
      rig.model.dateFilter = filter
      await rig.model.refresh()
      return rig.ids()
    }
    #expect(await shown(.today) == ["now"])
    #expect(await shown(.week) == ["now", "yesterday", "fiveDays"])
    #expect(await shown(.month) == ["now", "yesterday", "fiveDays", "twentyDays"])
    #expect(await shown(.all).count == 5)
    rig.model.stop()
  }

  @Test func searchWaitsForAPauseOnTheInjectedClock() async {
    let rig = HistoryModelRig()
    await rig.add("1", age: 3, title: "Deploy finished")
    await rig.add("2", age: 2, title: "Disk full")
    await rig.start()
    rig.model.searchText = "dep"
    #expect(await rig.eventually { rig.pipeline.clock.sleeperCount == 1 })
    #expect(rig.ids() == ["2", "1"])
    rig.pipeline.clock.advance(by: .milliseconds(200))
    rig.model.searchText = "deploy"
    #expect(await rig.eventually { rig.pipeline.clock.sleeperCount == 1 })
    rig.pipeline.clock.advance(by: .milliseconds(200))
    await Task.yield()
    #expect(rig.ids() == ["2", "1"])
    rig.pipeline.clock.advance(by: .milliseconds(100))
    #expect(await rig.eventually { rig.ids() == ["1"] })
    #expect(rig.model.resultCount == 1)
    rig.model.stop()
  }

  @Test func clearingTheSearchAppliesAtOnce() async {
    let rig = HistoryModelRig()
    await rig.add("1", age: 3, title: "Deploy")
    await rig.add("2", age: 2, title: "Disk")
    await rig.start()
    rig.model.searchText = "deploy"
    #expect(await rig.eventually { rig.pipeline.clock.sleeperCount == 1 })
    rig.pipeline.clock.advance(by: .milliseconds(300))
    #expect(await rig.eventually { rig.ids() == ["1"] })
    rig.model.searchText = "  "
    #expect(await rig.eventually { rig.ids() == ["2", "1"] })
    #expect(!rig.model.isFiltering)
    rig.model.stop()
  }

  @Test func textTheSearchCannotUseShowsNothingInsteadOfFailing() async {
    let rig = HistoryModelRig()
    await rig.add("1")
    await rig.start()
    rig.model.searchText = "\"(*"
    #expect(await rig.eventually { rig.pipeline.clock.sleeperCount == 1 })
    rig.pipeline.clock.advance(by: .milliseconds(300))
    #expect(await rig.eventually { rig.ids().isEmpty })
    #expect(rig.model.resultCount == 0)
    rig.model.stop()
  }

  @Test func resetFiltersDropsEverything() async {
    let rig = HistoryModelRig()
    await rig.add("1", priority: .low)
    await rig.start()
    rig.model.selectedTopic = "alerts"
    rig.model.minPriority = .max
    rig.model.dateFilter = .today
    rig.model.unreadOnly = true
    await rig.model.refresh()
    #expect(rig.ids().isEmpty)
    rig.model.resetFilters()
    await rig.model.refresh()
    #expect(rig.ids() == ["1"])
    #expect(!rig.model.isFiltering)
    rig.model.stop()
  }
}

@MainActor @Suite struct HistoryModelPagingTests {
  @Test func morePagesLoadUntilEverythingShows() async {
    let rig = HistoryModelRig(pageSize: 2)
    for index in 0..<5 { await rig.add("m\(index)", age: Double(10 - index)) }
    await rig.start()
    #expect(rig.ids() == ["m4", "m3"])
    #expect(rig.model.resultCount == 5)
    #expect(rig.model.hasMore)
    await rig.model.loadMore()
    #expect(rig.ids() == ["m4", "m3", "m2", "m1"])
    await rig.model.loadMore()
    #expect(rig.ids().count == 5)
    #expect(!rig.model.hasMore)
    await rig.model.loadMore()
    #expect(rig.ids().count == 5)
    rig.model.stop()
  }

  @Test func aChangeKeepsTheLoadedPagesAndAFilterGoesBackToTheFirst() async {
    let rig = HistoryModelRig(pageSize: 2)
    for index in 0..<4 { await rig.add("m\(index)", age: Double(10 - index)) }
    await rig.start()
    await rig.model.loadMore()
    #expect(rig.ids().count == 4)
    await rig.add("new", age: -1)
    #expect(await rig.eventually { rig.model.resultCount == 5 })
    #expect(rig.ids() == ["new", "m3", "m2", "m1"])
    rig.model.unreadOnly = true
    await rig.model.refresh()
    #expect(rig.ids().count == 2)
    #expect(rig.model.hasMore)
    rig.model.stop()
  }
}

@MainActor @Suite struct HistoryModelFollowTests {
  @Test func aNewMessageAppearsThroughTheChangeSignal() async {
    let rig = HistoryModelRig()
    await rig.start()
    #expect(rig.ids().isEmpty)
    await rig.add("fresh", topic: "news")
    #expect(await rig.eventually { rig.ids() == ["fresh"] })
    #expect(rig.model.topics.map(\.topic) == ["news"])
    rig.model.stop()
  }

  @Test func aRebuiltPipelineIsFollowedAndAnAbsentOneIsNotAvailable() async {
    let rig = HistoryModelRig()
    await rig.add("old")
    await rig.start()
    #expect(rig.ids() == ["old"])
    rig.source.set(nil)
    #expect(await rig.eventually { !rig.model.isAvailable })
    let next = PipelineFixture()
    _ = try? await next.history.append(next.message("other", topic: "elsewhere"))
    rig.source.set(next.handles)
    #expect(await rig.eventually { rig.ids() == ["other"] })
    #expect(rig.model.isAvailable)
    _ = try? await next.history.append(next.message("later", topic: "elsewhere", age: -1))
    #expect(await rig.eventually { rig.ids() == ["later", "other"] })
    rig.model.stop()
  }

  @Test func stopFollowingKeepsTheLastValues() async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    rig.model.stop()
    await rig.add("b")
    for _ in 0..<500 { await Task.yield() }
    #expect(rig.ids() == ["a"])
  }
}

@MainActor @Suite struct HistoryModelSelectionTests {
  @Test func selectingAMessageShowsItAndMarksItRead() async {
    let rig = HistoryModelRig()
    await rig.add("a", age: 2)
    await rig.add("b", age: 1)
    await rig.start()
    #expect(rig.model.totalUnread == 2)
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    #expect(rig.model.selection == MessageKey(topic: "alerts", id: "a"))
    #expect(rig.model.detail?.key.id == "a")
    #expect(rig.model.detail?.isRead == true)
    #expect(rig.model.rows.first { $0.key.id == "a" }?.isRead == true)
    #expect(rig.model.rows.first { $0.key.id == "b" }?.isRead == false)
    #expect(rig.model.totalUnread == 1)
    rig.model.stop()
  }

  @Test func theBindingSetterSelectsToo() async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    rig.model.setSelection(MessageKey(topic: "alerts", id: "a"))
    #expect(await rig.eventually { rig.model.detail?.isRead == true })
    rig.model.setSelection(nil)
    #expect(await rig.eventually { rig.model.detail == nil })
    #expect(rig.model.selection == nil)
    rig.model.stop()
  }

  @Test func theSelectionSurvivesFiltersThatHideIt() async {
    let rig = HistoryModelRig()
    await rig.add("a", priority: .low)
    await rig.start()
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    rig.model.minPriority = .max
    await rig.model.refresh()
    #expect(rig.ids().isEmpty)
    #expect(rig.model.detail?.key.id == "a")
    rig.model.stop()
  }

  @Test func aMessageThatVanishesClearsTheSelection() async {
    let rig = HistoryModelRig()
    await rig.add("a", sequenceID: "seq")
    await rig.start()
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    await rig.pipeline.history.withdraw(topic: "alerts", sequenceID: "seq")
    #expect(await rig.eventually { rig.model.selection == nil })
    #expect(rig.model.detail == nil)
    rig.model.stop()
  }

  @Test func anUnknownKeyClearsItselfAndMarksNothing() async {
    let rig = HistoryModelRig()
    await rig.add("a")
    await rig.start()
    await rig.model.select(MessageKey(topic: "alerts", id: "ghost"))
    #expect(rig.model.selection == nil)
    #expect(rig.model.totalUnread == 1)
    rig.model.stop()
  }

  @Test func theRouterHandoffDropsFiltersAndSelectsTheMessage() async {
    let rig = HistoryModelRig()
    await rig.add("a", topic: "alerts", age: 2)
    await rig.add("b", topic: "builds", age: 1, priority: .low)
    await rig.start()
    await rig.model.select(MessageKey(topic: "alerts", id: "a"))
    rig.model.minPriority = .max
    rig.model.searchText = "zzz"
    await rig.model.apply(selection: MessageKey(topic: "builds", id: "b"))
    #expect(rig.model.selectedTopic == "builds")
    #expect(rig.model.minPriority == nil)
    #expect(rig.model.searchText.isEmpty)
    #expect(rig.model.selection == MessageKey(topic: "builds", id: "b"))
    #expect(rig.model.detail?.isRead == true)
    #expect(rig.ids() == ["b"])
    rig.model.stop()
  }
}

@MainActor @Suite struct HistoryModelDetailTests {
  @Test func theDetailIsADisplayModel() async throws {
    let rig = HistoryModelRig()
    let attachment = MessageAttachment(
      url: URL(string: "https://e.com/a.png")!, name: "a.png", mimeType: "image/png", size: 9,
      expires: rig.pipeline.clock.now().addingTimeInterval(60))
    let actions = [
      MessageAction(kind: .view, label: "Open", url: URL(string: "https://e.com/x")),
      MessageAction(kind: .view, label: "Bad", url: URL(string: "file:///etc/passwd")),
      MessageAction(kind: .http, label: "Run", url: URL(string: "https://e.com/h")),
    ]
    await rig.add(
      "m", title: "Hello", body: "# Heading", priority: .high, tags: ["warning", "mine"],
      click: URL(string: "https://e.com/c"), attachment: attachment, actions: actions,
      contentType: "text/markdown")
    await rig.start()
    await rig.model.select(MessageKey(topic: "alerts", id: "m"))
    let detail = try #require(rig.model.detail)
    #expect(detail.title == "Hello" && detail.hasTitle)
    #expect(detail.body == "# Heading")
    #expect(detail.isMarkdown)
    #expect(detail.tags == ["warning", "mine"])
    #expect(detail.tagLabels == [TagEmoji.emoji(for: "warning") ?? "warning", "mine"])
    #expect(detail.priority == .high)
    #expect(detail.time == rig.pipeline.clock.now())
    #expect(detail.clickURL == URL(string: "https://e.com/c"))
    #expect(detail.actions.map(\.label) == ["Open", "Bad", "Run"])
    #expect(
      detail.actions.map(\.url?.absoluteString) == ["https://e.com/x", nil, "https://e.com/h"])
    #expect(detail.actions.map(\.kind) == ["view", "view", "http"])
    let file = try #require(detail.attachment)
    #expect(file.name == "a.png" && file.isImage && !file.isExpired && file.size == 9)
    rig.model.stop()
  }

  @Test func aClickURLTheAppWouldNotOpenIsDropped() async {
    let rig = HistoryModelRig()
    await rig.add("m", click: URL(string: "javascript:alert(1)"))
    await rig.start()
    await rig.model.select(MessageKey(topic: "alerts", id: "m"))
    #expect(rig.model.detail?.clickURL == nil)
    #expect(await rig.model.openClickURL() == false)
    #expect(await rig.opener.opened.isEmpty)
    rig.model.stop()
  }

  @Test func plainTextAndUntitledMessagesFallBack() async {
    let rig = HistoryModelRig()
    await rig.add("m", body: "first line\nsecond")
    await rig.start()
    await rig.model.select(MessageKey(topic: "alerts", id: "m"))
    #expect(rig.model.detail?.title == "first line")
    #expect(rig.model.detail?.hasTitle == false)
    #expect(rig.model.detail?.isMarkdown == false)
    #expect(rig.model.detail?.attachment == nil)
    rig.model.stop()
  }

  @Test func openingTheClickURLGoesThroughTheLinkOpener() async {
    let rig = HistoryModelRig()
    await rig.add("m", click: URL(string: "https://e.com/c"))
    await rig.start()
    #expect(await rig.model.openClickURL() == false)
    await rig.model.select(MessageKey(topic: "alerts", id: "m"))
    #expect(await rig.model.openClickURL())
    #expect(await rig.opener.opened == [URL(string: "https://e.com/c")!])
    rig.model.stop()
  }
}
