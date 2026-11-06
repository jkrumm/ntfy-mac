import Foundation
import NtfyCore

/// The recorded Team ID in a one-line file (`team-pin`). Not a secret; written atomically.
public struct FileTeamPinStore: TeamPinStoring {
  public static let fileName = "team-pin"

  /// `<application support>/ntfy-mac/team-pin`, next to the history database and the socket.
  public static func defaultURL(applicationSupport: URL) -> URL {
    applicationSupport
      .appending(path: "ntfy-mac", directoryHint: .isDirectory)
      .appending(path: fileName, directoryHint: .notDirectory)
  }

  private let url: URL

  public init(url: URL) { self.url = url }

  public func recorded() throws(NtfyError) -> String? {
    guard let data = try AtomicFile.read(url) else { return nil }
    let text = (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  public func record(_ teamID: String) throws(NtfyError) {
    try AtomicFile.write(Data((teamID + "\n").utf8), to: url)
  }
}
