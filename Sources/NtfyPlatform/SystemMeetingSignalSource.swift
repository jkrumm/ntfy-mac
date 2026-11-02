import AppKit
import CoreAudio
import CoreMediaIO
import NtfyCore

/// Reads which processes use the microphone or speakers, whether a camera is capturing, and
/// which apps run, and says when the first two may have changed.
///
/// Nothing here opens a microphone or a camera, records, or looks at a window, so macOS never
/// asks for a permission because of it: the audio and camera systems only report "in use".
public struct SystemMeetingSignalSource: MeetingSignalSource {
  private let ownPID: Int32

  public init(ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
    self.ownPID = ownPID
  }

  public func snapshot() async -> MeetingSnapshot {
    let apps = await MainActor.run {
      Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
    return MeetingSnapshot(
      audio: CoreAudioProcessList.read(LiveAudioObjects()),
      camera: CoreMediaCamera.read(LiveCameras()), runningApps: apps, ownPID: ownPID)
  }

  /// Listeners live as long as the stream is iterated.
  public func changes() -> AsyncStream<Void> {
    AsyncStream(Void.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
      let listeners = MeetingListeners { continuation.yield() }
      listeners.start()
      continuation.onTermination = { _ in listeners.stop() }
    }
  }
}

/// Property listeners on the process list, on each process's input and output flags, on the
/// camera list and on each camera's running flag. All state lives on `queue`, which is also
/// where the listener blocks run.
final class MeetingListeners: @unchecked Sendable {
  private let queue = DispatchQueue(label: "\(Log.subsystem).meeting")
  private let notify: @Sendable () -> Void
  private var audioBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
  private var cameraBlocks: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
  private var processListBlock: AudioObjectPropertyListenerBlock?
  private var cameraListBlock: CMIOObjectPropertyListenerBlock?
  private var stopped = false

  private static let processSelectors = [
    kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput,
  ]

  init(notify: @escaping @Sendable () -> Void) {
    self.notify = notify
  }

  func start() {
    queue.async { [self] in
      guard !stopped else { return }
      installProcessListListener()
      installCameraListListener()
      syncProcessListeners()
      syncCameraListeners()
    }
  }

  func stop() {
    queue.async { [self] in
      stopped = true
      removeProcessListeners()
      removeCameraListeners()
      if let block = processListBlock {
        var address = LiveAudioObjects.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(LiveAudioObjects.system, &address, queue, block)
        processListBlock = nil
      }
      if let block = cameraListBlock {
        var address = LiveCameras.address(kCMIOHardwarePropertyDevices)
        CMIOObjectRemovePropertyListenerBlock(LiveCameras.system, &address, queue, block)
        cameraListBlock = nil
      }
    }
  }

  // MARK: Audio

  private func installProcessListListener() {
    var address = LiveAudioObjects.address(kAudioHardwarePropertyProcessObjectList)
    let block: AudioObjectPropertyListenerBlock = { [self] _, _ in
      syncProcessListeners()
      notify()
    }
    guard
      AudioObjectAddPropertyListenerBlock(LiveAudioObjects.system, &address, queue, block)
        == noErr
    else { return }
    processListBlock = block
  }

  /// Listens on every process that is new and drops the listeners of those that are gone.
  private func syncProcessListeners() {
    guard !stopped else { return }
    let current = Set(LiveAudioObjects().processObjects() ?? [])
    for object in audioBlocks.keys where !current.contains(object) {
      removeProcessListeners(of: object)
    }
    for object in current where audioBlocks[object] == nil {
      let block: AudioObjectPropertyListenerBlock = { [self] _, _ in notify() }
      var installed = false
      for selector in Self.processSelectors {
        var address = LiveAudioObjects.address(selector)
        installed =
          AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr || installed
      }
      if installed { audioBlocks[object] = block }
    }
  }

  private func removeProcessListeners(of object: AudioObjectID) {
    guard let block = audioBlocks.removeValue(forKey: object) else { return }
    for selector in Self.processSelectors {
      var address = LiveAudioObjects.address(selector)
      AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
  }

  private func removeProcessListeners() {
    for object in Array(audioBlocks.keys) { removeProcessListeners(of: object) }
  }

  // MARK: Cameras

  private func installCameraListListener() {
    var address = LiveCameras.address(kCMIOHardwarePropertyDevices)
    let block: CMIOObjectPropertyListenerBlock = { [self] _, _ in
      syncCameraListeners()
      notify()
    }
    guard
      CMIOObjectAddPropertyListenerBlock(LiveCameras.system, &address, queue, block) == 0
    else { return }
    cameraListBlock = block
  }

  private func syncCameraListeners() {
    guard !stopped else { return }
    let current = Set(LiveCameras().devices() ?? [])
    for device in cameraBlocks.keys where !current.contains(device) {
      removeCameraListeners(of: device)
    }
    for device in current where cameraBlocks[device] == nil {
      let block: CMIOObjectPropertyListenerBlock = { [self] _, _ in notify() }
      var address = LiveCameras.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
      if CMIOObjectAddPropertyListenerBlock(device, &address, queue, block) == 0 {
        cameraBlocks[device] = block
      }
    }
  }

  private func removeCameraListeners(of device: CMIOObjectID) {
    guard let block = cameraBlocks.removeValue(forKey: device) else { return }
    var address = LiveCameras.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
    CMIOObjectRemovePropertyListenerBlock(device, &address, queue, block)
  }

  private func removeCameraListeners() {
    for device in Array(cameraBlocks.keys) { removeCameraListeners(of: device) }
  }
}
