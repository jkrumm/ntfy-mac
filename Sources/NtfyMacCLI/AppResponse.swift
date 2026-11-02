import NtfyCore
import NtfyIPC

extension Response {
  /// The result of a successful request; an error response becomes the failure it stands for.
  func requireSuccess() throws -> ResultPayload? {
    guard status == .error else { return result }
    let text = message ?? "the app reported an error"
    switch code {
    case .permissionDenied?:
      throw CLIFailure(code: "permission-denied", message: text, exit: .appUnavailable)
    case .appUnavailable?:
      throw CLIFailure(code: "app-unavailable", message: text, exit: .appUnavailable)
    case .badRequest?:
      throw CLIFailure.usage(text)
    default:
      throw CLIFailure.runtime(code?.rawValue ?? "app-error", text)
    }
  }
}
