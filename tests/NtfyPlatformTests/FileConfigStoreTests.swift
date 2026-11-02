import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

@Suite struct FileConfigStoreTests {
  @Test func missingFileLoadsEmpty() async {
    let dir = TempDirectory()
    let store = FileConfigStore(url: dir.file("sub/config.json"))
    #expect(await store.load() == Config())
  }

  @Test(arguments: ["", "not json", "[1]", "{\"url\":"])
  func malformedFileLoadsEmpty(content: String) async throws {
    let dir = TempDirectory()
    try dir.write(content, to: "config.json")
    #expect(await FileConfigStore(url: dir.file("config.json")).load() == Config())
  }

  @Test func checkedLoadTreatsMissingAndBlankAsEmpty() async throws {
    let dir = TempDirectory()
    let store = FileConfigStore(url: dir.file("config.json"))
    #expect(try await store.loadChecked() == Config())
    try dir.write(" \n", to: "config.json")
    #expect(try await store.loadChecked() == Config())
  }

  @Test(arguments: ["not json", "[1]", "{\"url\":"])
  func checkedLoadRefusesAMalformedFile(content: String) async throws {
    let dir = TempDirectory()
    try dir.write(content, to: "config.json")
    let store = FileConfigStore(url: dir.file("config.json"))
    await #expect(throws: NtfyError.self) { try await store.loadChecked() }
  }

  @Test func readsA1xFile() async throws {
    let dir = TempDirectory()
    try dir.write(
      """
      {
        "url": "https://ntfy.example.com",
        "token": "tk_abc",
        "sounds": { "4": "Glass", "1": null },
        "dismiss": { "5": 0 },
        "extraTopics": ["alerts"]
      }
      """, to: "config.json")
    let config = await FileConfigStore(url: dir.file("config.json")).load()
    #expect(config.url == "https://ntfy.example.com")
    #expect(config.token == "tk_abc")
    #expect(config.sounds == [4: .named("Glass"), 1: .silent])
    #expect(config.dismiss == [5: 0])
    #expect(config.extraTopics == ["alerts"])
  }

  @Test func saveCreatesDirectoryAndFileWithPrivateModes() async throws {
    let dir = TempDirectory()
    let path = dir.file("nested/config.json")
    let store = FileConfigStore(url: path)
    try await store.save(Config(url: "https://n.example.com"))
    #expect(try dir.permissions(path) == 0o600)
    #expect(try dir.permissions(path.deletingLastPathComponent()) == 0o700)
    let text = try dir.read("nested/config.json")
    #expect(text.hasSuffix("\n"))
    #expect(await store.load().url == "https://n.example.com")
  }

  @Test func saveLeavesNoTempFilesBehind() async throws {
    let dir = TempDirectory()
    let store = FileConfigStore(url: dir.file("config.json"))
    for index in 0..<5 { try await store.save(Config(url: "https://n\(index).example.com")) }
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
    #expect(names.sorted() == ["config.json", "config.json.lock"])
  }

  @Test func unknownKeysSurviveSaves() async throws {
    let dir = TempDirectory()
    try dir.write(#"{"url":"https://a.example.com","somethingNew":{"x":[1,2]}}"#, to: "config.json")
    let store = FileConfigStore(url: dir.file("config.json"))
    try await store.update { $0.dismiss[3] = 20 }
    let text = try dir.read("config.json")
    #expect(text.contains("somethingNew"))
    #expect(text.contains("\"url\""))
    let config = await store.load()
    #expect(config.dismiss == [3: 20])
    #expect(config.extras["somethingNew"] != nil)
  }

  @Test func saveRefusesToClobberAMalformedFile() async throws {
    let dir = TempDirectory()
    try dir.write("{ hand edited, oops", to: "config.json")
    let store = FileConfigStore(url: dir.file("config.json"))
    await #expect(throws: NtfyError.self) {
      try await store.save(Config(url: "https://n.example.com"))
    }
    await #expect(throws: NtfyError.self) { try await store.update { $0.url = "x" } }
    #expect(try dir.read("config.json") == "{ hand edited, oops")
  }

  @Test func saveOverwritesAnEmptyFile() async throws {
    let dir = TempDirectory()
    try dir.write("\n", to: "config.json")
    let store = FileConfigStore(url: dir.file("config.json"))
    try await store.save(Config(url: "https://n.example.com"))
    #expect(await store.load().url == "https://n.example.com")
  }

  @Test func concurrentUpdatesDoNotLoseEachOther() async throws {
    let dir = TempDirectory()
    let store = FileConfigStore(url: dir.file("config.json"))
    try await withThrowingTaskGroup(of: Void.self) { group in
      for priority in 1...5 {
        group.addTask { try await store.update { $0.dismiss[priority] = Double(priority) } }
      }
      try await group.waitForAll()
    }
    #expect(await store.load().dismiss.count == 5)
  }
}
