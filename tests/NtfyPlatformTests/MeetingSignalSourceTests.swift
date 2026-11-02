import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

private struct FakeAudio: AudioObjectAccess {
  var objects: [UInt32]?
  var pids: [UInt32: Int32] = [:]
  var bundles: [UInt32: String] = [:]
  var inputs: Set<UInt32> = []
  var outputs: Set<UInt32> = []
  var unreadableFlags: Set<UInt32> = []

  func processObjects() -> [UInt32]? { objects }
  func pid(of object: UInt32) -> Int32? { pids[object] }
  func bundleID(of object: UInt32) -> String? { bundles[object] }
  func isRunningInput(_ object: UInt32) throws(PropertyReadFailure) -> Bool {
    if unreadableFlags.contains(object) { throw PropertyReadFailure() }
    return inputs.contains(object)
  }
  func isRunningOutput(_ object: UInt32) throws(PropertyReadFailure) -> Bool {
    if unreadableFlags.contains(object) { throw PropertyReadFailure() }
    return outputs.contains(object)
  }
}

private struct FakeCameras: CameraAccess {
  var list: [UInt32]?
  /// A device without an entry fails to read.
  var running: [UInt32: Bool] = [:]

  func devices() -> [UInt32]? { list }
  func isRunningSomewhere(_ device: UInt32) throws(PropertyReadFailure) -> Bool {
    guard let value = running[device] else { throw PropertyReadFailure() }
    return value
  }
}

@Suite struct CoreAudioProcessListTests {
  @Test func mapsEachProcessWithItsFlags() {
    let audio = FakeAudio(
      objects: [1, 2], pids: [1: 100, 2: 200], bundles: [1: "us.zoom.xos"], inputs: [1],
      outputs: [1, 2])
    #expect(
      CoreAudioProcessList.read(audio) == [
        AudioProcessState(
          pid: 100, bundleID: "us.zoom.xos", isRunningInput: true, isRunningOutput: true),
        AudioProcessState(pid: 200, bundleID: "", isRunningInput: false, isRunningOutput: true),
      ])
  }

  @Test func anUnreadableListIsUnknownNotEmpty() {
    #expect(CoreAudioProcessList.read(FakeAudio(objects: nil)) == nil)
    #expect(CoreAudioProcessList.read(FakeAudio(objects: [])) == [])
  }

  @Test func aProcessThatCannotBeReadIsLeftOut() {
    let audio = FakeAudio(
      objects: [1, 2, 3], pids: [1: 10, 2: 20], inputs: [1, 2], unreadableFlags: [2])
    #expect(CoreAudioProcessList.read(audio)?.map(\.pid) == [10])
  }
}

@Suite struct CoreMediaCameraTests {
  @Test func noCameraMeansIdle() {
    #expect(CoreMediaCamera.read(FakeCameras(list: [])) == .idle)
  }

  @Test func anUnreadableDeviceListIsUnknown() {
    #expect(CoreMediaCamera.read(FakeCameras(list: nil)) == .unknown)
  }

  @Test func anyRunningDeviceMeansRunning() {
    let cameras = FakeCameras(list: [1, 2], running: [1: false, 2: true])
    #expect(CoreMediaCamera.read(cameras) == .running)
  }

  @Test func aFailedReadIsUnknownUnlessAnotherDeviceRuns() {
    #expect(
      CoreMediaCamera.read(FakeCameras(list: [1, 2], running: [1: false])) == .unknown)
    #expect(
      CoreMediaCamera.read(FakeCameras(list: [1, 2], running: [2: true])) == .running)
  }

  @Test func allIdleMeansIdle() {
    #expect(CoreMediaCamera.read(FakeCameras(list: [1], running: [1: false])) == .idle)
  }
}

/// Reads this Mac for real. It only asks the audio and camera systems what is in use, so it
/// never prompts; it is skipped where the audio system has no process list.
@Suite struct SystemMeetingSignalSourceLiveTests {
  private static let hasProcessList = CoreAudioProcessList.read(LiveAudioObjects()) != nil

  @Test(.enabled(if: hasProcessList))
  func aLiveSnapshotHasAnAudioListAndACameraReading() async throws {
    let snapshot = await SystemMeetingSignalSource().snapshot()
    let audio = try #require(snapshot.audio)
    #expect(audio.allSatisfy { $0.pid > 0 })
    #expect(snapshot.ownPID == ProcessInfo.processInfo.processIdentifier)
  }

  @Test func theChangeStreamStartsAndStopsCleanly() async {
    let task = Task {
      for await _ in SystemMeetingSignalSource().changes() { break }
    }
    try? await Task.sleep(for: .milliseconds(200))
    task.cancel()
    await task.value
  }
}
