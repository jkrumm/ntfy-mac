import Foundation

/// Where the app's socket lives and how it is made safe to use.
public enum SocketPath {
  public static let directoryName = "ntfy-mac"
  public static let fileName = "app.sock"
  /// `sockaddr_un.sun_path` holds 104 bytes including the terminating NUL.
  public static let maxLength = 103

  /// `<application support>/ntfy-mac/app.sock`, next to the history database.
  public static func `default`(applicationSupport: URL) -> URL {
    applicationSupport
      .appending(path: directoryName, directoryHint: .isDirectory)
      .appending(path: fileName, directoryHint: .notDirectory)
  }

  public static func validate(_ url: URL) throws(IPCError) {
    guard url.path.utf8.count <= maxLength else { throw .pathTooLong }
  }

  /// Creates the directory (0700) and tightens it when it already exists.
  static func prepareDirectory(of socket: URL) throws(IPCError) {
    let directory = socket.deletingLastPathComponent().path
    do {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
    } catch {
      throw .system("prepare directory", errno)
    }
  }
}
