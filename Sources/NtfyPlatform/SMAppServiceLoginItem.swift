import NtfyCore
import ServiceManagement

/// The main app's login item through `SMAppService.mainApp`. Only the app process may use it:
/// the registration belongs to the bundle that is running.
public struct SMAppServiceLoginItem: LoginItemControlling {
  public init() {}

  public func state() -> LoginItemState {
    Self.map(SMAppService.mainApp.status)
  }

  public func setEnabled(_ enabled: Bool) throws(NtfyError) -> LoginItemState {
    let service = SMAppService.mainApp
    do {
      if enabled {
        if service.status != .enabled { try service.register() }
      } else if service.status != .notRegistered {
        try service.unregister()
      }
    } catch {
      throw .storage("cannot change the login item: \(error.localizedDescription)")
    }
    return Self.map(service.status)
  }

  static func map(_ status: SMAppService.Status) -> LoginItemState {
    switch status {
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notRegistered: .notRegistered
    case .notFound: .notFound
    @unknown default: .notFound
    }
  }
}
