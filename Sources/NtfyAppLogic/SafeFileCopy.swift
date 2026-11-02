import Foundation

/// Copies a file over a destination the user chose, without ever losing the destination: the
/// copy is made next to it first and swapped in only once complete.
public enum SafeFileCopy {
  /// Does nothing when `source` and `destination` are the same file (the user picked the file
  /// itself). A failed copy leaves an existing destination untouched.
  public static func copy(_ source: URL, to destination: URL) throws {
    let files = FileManager.default
    guard !isSameFile(source, destination) else { return }
    let directory = destination.deletingLastPathComponent()
    let staged = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
    try files.copyItem(at: source, to: staged)
    do {
      if files.fileExists(atPath: destination.path) {
        _ = try files.replaceItemAt(destination, withItemAt: staged)
      } else {
        try files.moveItem(at: staged, to: destination)
      }
    } catch {
      try? files.removeItem(at: staged)
      throw error
    }
  }

  static func isSameFile(_ first: URL, _ second: URL) -> Bool {
    if first.resolvingSymlinksInPath().standardizedFileURL
      == second.resolvingSymlinksInPath().standardizedFileURL
    {
      return true
    }
    let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
    guard let one = try? first.resourceValues(forKeys: keys).fileResourceIdentifier,
      let two = try? second.resourceValues(forKeys: keys).fileResourceIdentifier
    else { return false }
    return one.isEqual(two)
  }
}
