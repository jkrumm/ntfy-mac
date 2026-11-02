import CoreMediaIO
import Foundation
import NtfyCore

/// The property reads the camera check needs. Every read fails (or returns nil) when the system
/// could not answer.
protocol CameraAccess: Sendable {
  func devices() -> [UInt32]?
  func isRunningSomewhere(_ device: UInt32) throws(PropertyReadFailure) -> Bool
}

/// Whether any camera is capturing, from CoreMediaIO's `DeviceIsRunningSomewhere`. It needs no
/// Camera permission and shows no prompt, and it does not say which app holds the camera.
enum CoreMediaCamera {
  /// Running when any device is; idle when every device was read and none is (also when there
  /// is no camera at all); unknown when a read failed and nothing else says running.
  static func read(_ access: some CameraAccess) -> CameraState {
    guard let devices = access.devices() else { return .unknown }
    var unreadable = false
    for device in devices {
      do throws(PropertyReadFailure) {
        if try access.isRunningSomewhere(device) { return .running }
      } catch {
        unreadable = true
      }
    }
    return unreadable ? .unknown : .idle
  }
}

/// The real camera system.
struct LiveCameras: CameraAccess {
  static let system = CMIOObjectID(kCMIOObjectSystemObject)

  static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(selector),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
  }

  func devices() -> [UInt32]? {
    var address = Self.address(kCMIOHardwarePropertyDevices)
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(Self.system, &address, 0, nil, &size) == 0 else {
      return nil
    }
    var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(Self.system, &address, 0, nil, size, &used, &devices) == 0
    else { return nil }
    return Array(devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
  }

  func isRunningSomewhere(_ device: UInt32) throws(PropertyReadFailure) -> Bool {
    var address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
    var value: UInt32 = 0
    var used: UInt32 = 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &value) == 0 else {
      throw PropertyReadFailure()
    }
    return value != 0
  }
}
