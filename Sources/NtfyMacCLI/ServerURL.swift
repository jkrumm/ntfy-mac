import Foundation
import NtfyCore

/// A server address as the user types it.
enum ServerURL {
  /// See `ServerAddress.parse`; failures are usage errors.
  static func parse(_ input: String) throws -> URL {
    do {
      return try ServerAddress.parse(input)
    } catch {
      throw CLIFailure.usage(error.description)
    }
  }
}
