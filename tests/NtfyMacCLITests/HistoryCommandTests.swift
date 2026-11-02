import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct HistoryCommandTests {
  private func messages(_ result: RunResult) throws -> [[String: Any]] {
    let data = try #require(result.stdout.data(using: .utf8))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
  }

  private func ids(_ result: RunResult) throws -> [String] {
    try messages(result).compactMap { $0["id"] as? String }
  }

  private func seeded() async -> CLIRig {
    let rig = CLIRig()
    await rig.add("alerts", id: "a1", body: "disk full", title: "Disk", priority: 5, age: 600)
    await rig.add("alerts", id: "a2", body: "deploy done", priority: 3, age: 300)
    await rig.add("builds", id: "b1", body: "build passed", priority: 2, age: 100, tags: ["ok"])
    await rig.add("builds", id: "b2", body: "build failed", priority: 4, age: 10)
    return rig
  }

  // MARK: ls

  @Test func lsListsNewestFirstWithTheStableJSONShape() async throws {
    let rig = await seeded()
    let result = await rig.run("ls", "--json")
    #expect(result.exit == .success)
    let list = try messages(result)
    #expect(list.compactMap { $0["id"] as? String } == ["b2", "b1", "a2", "a1"])
    let first = try #require(list.first)
    #expect(
      Set(first.keys) == [
        "topic", "id", "time", "title", "message", "priority", "tags", "read", "acknowledged",
        "click", "attachments",
      ])
    #expect(first["topic"] as? String == "builds")
    #expect(first["message"] as? String == "build failed")
    #expect(first["priority"] as? Int == 4)
    #expect(first["title"] is NSNull)
    #expect(first["read"] as? Bool == false)
    #expect((first["attachments"] as? [Any])?.isEmpty == true)
    let time = try #require(first["time"] as? String)
    #expect(TimePoint.iso8601(time) != nil)
  }

  @Test func lsFiltersCombine() async throws {
    let rig = await seeded()
    #expect(try ids(await rig.run("ls", "--json", "--topic", "alerts")) == ["a2", "a1"])
    #expect(try ids(await rig.run("ls", "--json", "--min-priority", "4")) == ["b2", "a1"])
    #expect(try ids(await rig.run("ls", "--json", "--since", "200s")) == ["b2", "b1"])
    #expect(try ids(await rig.run("ls", "--json", "--limit", "1")) == ["b2"])
    let sinceISO = TimePoint.iso8601("2023-11-14T22:13:20Z")  // the rig clock's start
    #expect(sinceISO != nil)
    #expect(try ids(await rig.run("ls", "--json", "--since", "2023-11-14T22:13:20Z")) == [])
  }

  @Test func unreadAndUnackedFilters() async throws {
    let rig = await seeded()
    await rig.store.markRead(topic: "alerts", id: "a1")
    await rig.store.acknowledge(topic: "builds", id: "b2")
    #expect(try ids(await rig.run("ls", "--json", "--unread")) == ["b1", "a2"])
    #expect(try ids(await rig.run("ls", "--json", "--unacked")) == ["b1", "a2", "a1"])
    #expect(try ids(await rig.run("ls", "--json", "--unacked", "--limit", "2")) == ["b1", "a2"])
    let read = try messages(await rig.run("ls", "--json", "--topic", "alerts"))
    #expect(read.last?["read"] as? Bool == true)
  }

  @Test func lsTextIsATable() async {
    let rig = await seeded()
    let result = await rig.run("ls")
    #expect(result.exit == .success)
    let lines = result.stdoutLines
    #expect(lines.count == 4)
    #expect(lines[0].contains("builds") && lines[0].contains("b2") && lines[0].contains("p4"))
    #expect(lines[3].contains("Disk: disk full"))
  }

  @Test func anAbsentDatabaseIsAnEmptyResultNotAnError() async throws {
    var rig = CLIRig()
    rig.historyAbsent = true
    let json = await rig.run("ls", "--json")
    #expect(json.exit == .success)
    #expect(try messages(json).isEmpty)
    #expect(await rig.run("ls").stdout == "No messages.\n")
    #expect(await rig.run("search", "x", "--json").exit == .success)
    #expect(await rig.run("tail").stdout.isEmpty)
  }

  @Test(arguments: [
    ["ls", "--limit", "0"], ["ls", "--limit", "5000"], ["ls", "--min-priority", "6"],
    ["ls", "--since", "yesterday"], ["ls", "--topic", "bad topic"],
    ["search", "--limit", "x", "q"],
    ["search"], ["tail", "--min-priority", "0"],
  ])
  func badFlagValuesAreUsageErrors(arguments: [String]) async {
    let result = await CLIRig().run(arguments)
    #expect(result.exit == .usage, "\(arguments)")
  }

  // MARK: search

  @Test func searchMatchesWordPrefixesAndTakesTheFilters() async throws {
    let rig = await seeded()
    #expect(try ids(await rig.run("search", "build", "--json")) == ["b2", "b1"])
    #expect(try ids(await rig.run("search", "build", "--json", "--min-priority", "4")) == ["b2"])
    #expect(try ids(await rig.run("search", "disk", "--json")) == ["a1"])
    #expect(try ids(await rig.run("search", "nothing-like-it", "--json")) == [])
    #expect(try ids(await rig.run("search", "--json", "--", "!!!")) == [])
  }

  // MARK: read

  @Test func readPrintsTheMessageAndMarksItRead() async throws {
    let rig = await seeded()
    let result = await rig.run("read", "alerts", "a1", "--json")
    #expect(result.exit == .success)
    let message = try result.json()
    #expect(message["id"] as? String == "a1")
    #expect(message["read"] as? Bool == true)
    #expect(await rig.store.message(topic: "alerts", id: "a1")?.isRead == true)
  }

  @Test func readNoMarkLeavesTheStateAlone() async throws {
    let rig = await seeded()
    let result = await rig.run("read", "alerts", "a1", "--no-mark", "--json")
    #expect(try result.json()["read"] as? Bool == false)
    #expect(await rig.store.message(topic: "alerts", id: "a1")?.isRead == false)
  }

  @Test func readTextShowsTheFullMessage() async {
    let rig = await seeded()
    let result = await rig.run("read", "alerts", "a1")
    #expect(result.stdout.contains("alerts/a1"))
    #expect(result.stdout.contains("Title:    Disk"))
    #expect(result.stdout.contains("disk full"))
    #expect(result.stdout.contains("State:    read, unacknowledged"))
  }

  @Test func readOfAnUnknownMessageIsNotFound() async throws {
    let rig = await seeded()
    let result = await rig.run("read", "alerts", "nope", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "not-found")
    var absent = CLIRig()
    absent.historyAbsent = true
    #expect(await absent.run("read", "alerts", "a1").exit == .runtime)
  }

  // MARK: ack

  @Test func ackOneGoesThroughTheAppAndLaunchesIt() async throws {
    let rig = CLIRig()
    let result = await rig.run("ack", "alerts", "a1", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["acknowledged"] as? Int == 1)
    let call = try #require(await rig.app.calls.first)
    #expect(call.request.command == .ack)
    #expect(call.request.ack == MessageTarget(topic: "alerts", id: "a1"))
    #expect(call.launch)
  }

  @Test func ackAllCarriesTheTopicAndReportsTheCount() async throws {
    let app = FakeApp()
    await app.reply(
      to: .ackAll,
      with: .success(id: "x", result: ResultPayload(ackAll: AckAllResult(acknowledged: 3))))
    let rig = CLIRig(app: app)
    let result = await rig.run("ack", "--all", "--topic", "alerts", "--json")
    #expect(try result.json()["acknowledged"] as? Int == 3)
    let call = try #require(await app.calls.first)
    #expect(call.request.command == .ackAll)
    #expect(call.request.ackAll == AckAllPayload(topic: "alerts"))
    let text = await rig.run("ack", "--all")
    #expect(text.stdout == "Acknowledged 3 message(s).\n")
  }

  @Test func ackOfAnUnknownMessageExitsOneWithNotFound() async throws {
    let app = FakeApp()
    await app.reply(to: .ack, with: .failure(id: "x", code: .notFound, message: "no message"))
    let result = await CLIRig(app: app).run("ack", "alerts", "nope", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "not-found")
  }

  @Test func ackWithTheAppDownIsExitFour() async {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    #expect(await rig.run("ack", "alerts", "a1").exit == .appUnavailable)
    #expect(await rig.run("ack", "--all").exit == .appUnavailable)
  }

  @Test(arguments: [
    ["ack"], ["ack", "alerts"], ["ack", "--all", "alerts", "a1"],
    ["ack", "alerts", "a1", "--topic", "x"],
    ["ack", "--all", "--topic", "bad topic"],
  ])
  func ackNeedsExactlyOneForm(arguments: [String]) async {
    let rig = CLIRig()
    #expect(await rig.run(arguments).exit == .usage, "\(arguments)")
    #expect(await rig.app.calls.isEmpty)
  }

  // MARK: tail

  @Test func tailPrintsNDJSONOldestFirstEvenWithoutJSON() async throws {
    let rig = await seeded()
    for flags in [[], ["--json"]] {
      let result = await rig.run(["tail", "--limit", "3"] + flags)
      #expect(result.exit == .success)
      let ids = try result.stdoutLines.map { line -> String in
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        return try #require(object?["id"] as? String)
      }
      #expect(ids == ["a2", "b1", "b2"])
    }
  }

  @Test func tailFiltersByTopic() async {
    let result = await seeded().run("tail", "--topic", "alerts")
    #expect(result.stdoutLines.count == 2)
  }
}
