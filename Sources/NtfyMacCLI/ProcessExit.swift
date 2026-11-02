import ArgumentParser
import NtfyCore
import NtfyIPC

/// Process exit codes. The only place typed module errors become integers.
enum ProcessExit: Int32, CaseIterable {
  case success = 0
  case runtime = 1
  case usage = 2
  case auth = 3
  case appUnavailable = 4
  case serverUnreachable = 7

  init(error: any Error) {
    switch error {
    case let failure as CLIFailure:
      self = failure.exit
    case let request as ExitRequest:
      self = request.exit
    case let error as NtfyError:
      self.init(error)
    case is IPCError:
      self = .runtime
    case is ValidationError:
      self = .usage
    default:
      self = .runtime
    }
  }

  private init(_ error: NtfyError) {
    switch error {
    case .unauthorized: self = .auth
    case .serverUnreachable: self = .serverUnreachable
    case .appUnavailable, .permissionDenied: self = .appUnavailable
    case .invalidTopic: self = .usage
    case .rateLimited, .redirected, .insecureServer, .invalidResponse, .storage: self = .runtime
    }
  }
}
