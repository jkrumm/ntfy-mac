import Foundation

/// Where the history database lives; `SQLiteHistoryStore` opens it.
public enum StoreLocation {
  public static let directoryName = "ntfy-mac"
  public static let databaseFileName = "history.sqlite"

  /// `<application support>/ntfy-mac/history.sqlite`.
  public static func databaseURL(applicationSupport: URL) -> URL {
    applicationSupport
      .appending(path: directoryName, directoryHint: .isDirectory)
      .appending(path: databaseFileName, directoryHint: .notDirectory)
  }
}
