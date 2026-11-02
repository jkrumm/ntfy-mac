import CoreAudio
import Foundation
import NtfyCore

/// A property read the system refused or could not answer.
struct PropertyReadFailure: Error {}

/// The property reads the process list needs, so the mapping is testable without an audio
/// system. Every read fails (or returns nil) when the system could not answer.
protocol AudioObjectAccess: Sendable {
  func processObjects() -> [UInt32]?
  func pid(of object: UInt32) -> Int32?
  func bundleID(of object: UInt32) -> String?
  func isRunningInput(_ object: UInt32) throws(PropertyReadFailure) -> Bool
  func isRunningOutput(_ object: UInt32) throws(PropertyReadFailure) -> Bool
}

/// The audio system's per-process view (macOS 14 and later): which processes are using input
/// or output right now. Reading these properties needs no Microphone permission and shows no
/// prompt; they only report that a process is running audio, never what it hears.
enum CoreAudioProcessList {
  /// The processes known to the audio system, nil when the list itself cannot be read (unknown,
  /// never "nobody"). A process that vanishes between the list and its properties is left out.
  static func read(_ access: some AudioObjectAccess) -> [AudioProcessState]? {
    guard let objects = access.processObjects() else { return nil }
    return objects.compactMap { object in
      guard let pid = access.pid(of: object),
        let input = try? access.isRunningInput(object),
        let output = try? access.isRunningOutput(object)
      else { return nil }
      return AudioProcessState(
        pid: pid, bundleID: access.bundleID(of: object) ?? "", isRunningInput: input,
        isRunningOutput: output)
    }
  }
}

/// The real audio system.
struct LiveAudioObjects: AudioObjectAccess {
  static let system = AudioObjectID(kAudioObjectSystemObject)

  static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }

  func processObjects() -> [UInt32]? {
    var address = Self.address(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(Self.system, &address, 0, nil, &size) == noErr else {
      return nil
    }
    var objects = [AudioObjectID](
      repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &objects) == noErr
    else { return nil }
    return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
  }

  func pid(of object: UInt32) -> Int32? {
    scalar(object, kAudioProcessPropertyPID).map { Int32(bitPattern: $0) }
  }

  func isRunningInput(_ object: UInt32) throws(PropertyReadFailure) -> Bool {
    guard let value = scalar(object, kAudioProcessPropertyIsRunningInput) else {
      throw PropertyReadFailure()
    }
    return value != 0
  }

  func isRunningOutput(_ object: UInt32) throws(PropertyReadFailure) -> Bool {
    guard let value = scalar(object, kAudioProcessPropertyIsRunningOutput) else {
      throw PropertyReadFailure()
    }
    return value != 0
  }

  func bundleID(of object: UInt32) -> String? {
    var address = Self.address(kAudioProcessPropertyBundleID)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    guard status == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
  }

  private func scalar(_ object: UInt32, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var address = Self.address(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    return status == noErr ? value : nil
  }
}
