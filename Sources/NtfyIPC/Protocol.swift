import Foundation

/// Wire protocol between the CLI and the app: one JSON object per line.
public enum IPC {
  /// Bumped on every incompatible change; peers reject any other value.
  public static let protocolVersion = 1
}

public enum IPCError: Error, Sendable, Hashable {
  case unsupportedProtocolVersion(Int)
  case malformedFrame
}

/// Something that carries a protocol version on the wire.
public protocol Versioned: Codable, Sendable {
  var protocolVersion: Int { get }
}

public enum Command: String, Codable, Sendable, CaseIterable {
  case ping
  case reconnect
}

public struct Request: Versioned, Hashable {
  public let protocolVersion: Int
  public let id: String
  public let command: Command

  public init(id: String, command: Command, protocolVersion: Int = IPC.protocolVersion) {
    self.protocolVersion = protocolVersion
    self.id = id
    self.command = command
  }
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

  public init(
    id: String, status: Status, message: String? = nil,
    protocolVersion: Int = IPC.protocolVersion
  ) {
    self.protocolVersion = protocolVersion
    self.id = id
    self.status = status
    self.message = message
  }
}
