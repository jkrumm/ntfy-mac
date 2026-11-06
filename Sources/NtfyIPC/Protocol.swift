import Foundation

/// Wire protocol between the CLI and the app: one JSON object per line.
public enum IPC {
  /// Bumped on every incompatible change; peers reject any other value.
  public static let protocolVersion = 1
  /// What a server answers (`bad-request`) when it cannot decode a frame, which includes a
  /// command it does not know. A newer CLI recognises an older app by it.
  public static let invalidFrameMessage = "request is not a valid frame"
}

/// Something that carries a protocol version on the wire.
public protocol Versioned: Codable, Sendable {
  var protocolVersion: Int { get }
}

public enum Command: String, Codable, Sendable, CaseIterable {
  /// Liveness check.
  case ping
  /// Connection state, pause, app version and permission summary.
  case status
  /// Restarts the stream connection.
  case reconnect
  /// Posts a local notification (`Request.notify`).
  case notify
  /// Acknowledges a message (`Request.ack`).
  case ack
  /// Snoozes a message until a time (`Request.remind`).
  case remind
  /// Reads the notification permission state.
  case permission
  /// Acknowledges every unacknowledged message, optionally of one topic (`Request.ackAll`).
  case ackAll
  /// Reads or changes the login item registration (`Request.loginItem`).
  case loginItem
  /// Deletes one message, or every message of a topic, from the history (`Request.delete`).
  /// Added after the first v1 release: an older app answers `bad-request`.
  case delete
  /// Checks for an update, or starts the update flow (`Request.update`). Added after the first
  /// v1 release: an older app answers `bad-request`.
  case update
}

public struct Request: Versioned, Hashable {
  public let protocolVersion: Int
  public let id: String
  public let command: Command
  /// Payload of `Command.notify`.
  public let notify: NotifyPayload?
  /// Payload of `Command.ack`.
  public let ack: MessageTarget?
  /// Payload of `Command.remind`.
  public let remind: RemindPayload?
  /// Payload of `Command.ackAll`.
  public let ackAll: AckAllPayload?
  /// Payload of `Command.loginItem`.
  public let loginItem: LoginItemPayload?
  /// Payload of `Command.delete`.
  public let delete: DeletePayload?
  /// Payload of `Command.update`.
  public let update: UpdatePayload?

  public init(
    id: String, command: Command, notify: NotifyPayload? = nil, ack: MessageTarget? = nil,
    remind: RemindPayload? = nil, ackAll: AckAllPayload? = nil,
    loginItem: LoginItemPayload? = nil, delete: DeletePayload? = nil,
    update: UpdatePayload? = nil, protocolVersion: Int = IPC.protocolVersion
  ) {
    self.protocolVersion = protocolVersion
    self.id = id
    self.command = command
    self.notify = notify
    self.ack = ack
    self.remind = remind
    self.ackAll = ackAll
    self.loginItem = loginItem
    self.delete = delete
    self.update = update
  }
}

/// A stable, machine-readable reason for an error response. Unknown values decode fine, so a
/// newer app can add codes without breaking an older CLI.
public struct ErrorCode: RawRepresentable, Codable, Sendable, Hashable {
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// The pipeline is not running (not configured, or being rebuilt).
  public static let appUnavailable = ErrorCode(rawValue: "app-unavailable")
  public static let permissionDenied = ErrorCode(rawValue: "permission-denied")
  public static let badRequest = ErrorCode(rawValue: "bad-request")
  public static let unsupportedVersion = ErrorCode(rawValue: "unsupported-version")
  public static let notFound = ErrorCode(rawValue: "not-found")
  public static let internalError = ErrorCode(rawValue: "internal")
}

public struct Response: Versioned, Hashable {
  public enum Status: String, Codable, Sendable {
    case success = "ok"
    case error
  }

  public let protocolVersion: Int
  public let id: String
  public let status: Status
  public let message: String?
  /// Set on errors.
  public let code: ErrorCode?
  /// Set on success for commands that return data.
  public let result: ResultPayload?

  public init(
    id: String, status: Status, message: String? = nil, code: ErrorCode? = nil,
    result: ResultPayload? = nil, protocolVersion: Int = IPC.protocolVersion
  ) {
    self.protocolVersion = protocolVersion
    self.id = id
    self.status = status
    self.message = message
    self.code = code
    self.result = result
  }

  public static func success(id: String, result: ResultPayload? = nil) -> Response {
    Response(id: id, status: .success, result: result)
  }

  public static func failure(id: String, code: ErrorCode, message: String) -> Response {
    Response(id: id, status: .error, message: message, code: code)
  }
}
