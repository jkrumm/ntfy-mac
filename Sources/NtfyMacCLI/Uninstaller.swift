import Foundation
import NtfyCore

/// Removes everything ntfy-mac keeps outside the app bundle.
struct Uninstaller {
  struct Item {
    let label: String
    let url: URL
  }

  struct Report: Encodable {
    let removed: [String]
    let failed: [String]
    /// How to delete the app itself; the running bundle is never touched.
    let removeApp: [String]

    func text() -> String {
      var lines = removed.map { "Removed \($0)" } + failed.map { "Failed: \($0)" }
      lines += [
        "", "Quit the ntfy-mac app from the menu bar if it is still running.",
        "To remove the app itself:",
      ]
      lines += removeApp.map { "  \($0)" }
      return lines.joined(separator: "\n")
    }
  }

  let paths: CLIPaths
  let secrets: any SecretStore
  let app: any AppControlling

  var items: [Item] {
    [
      Item(label: "config", url: paths.configFile),
      Item(label: "config lock", url: paths.configLock),
      Item(label: "history and socket", url: paths.dataDirectory),
      Item(label: "state", url: paths.stateDirectory),
    ]
  }

  func run() async -> Report {
    var removed: [String] = []
    var failed: [String] = []
    if await removeLoginItem() { removed.append("login item") }
    for item in items where FileManager.default.fileExists(atPath: item.url.path) {
      do {
        try FileManager.default.removeItem(at: item.url)
        removed.append("\(item.label) (\(item.url.path))")
      } catch {
        failed.append("\(item.label): \(error.localizedDescription)")
      }
    }
    removeEmptyConfigDirectory()
    do {
      try await secrets.deleteToken()
      removed.append("access token (Keychain)")
    } catch {
      failed.append("Keychain token: \(error.cliMessage)")
    }
    return Report(
      removed: removed, failed: failed,
      removeApp: ["brew uninstall --cask ntfy-mac", "or delete NtfyMac.app"])
  }

  /// Unregisters the login item through the app, which alone can. Best effort: with the app
  /// not running there is nothing to ask, and the entry then disappears with the app bundle.
  /// True when a registration was removed.
  private func removeLoginItem() async -> Bool {
    let client = LoginItemClient(app: app)
    guard let before = try? await client.state(launch: false),
      before == .enabled || before == .requiresApproval
    else { return false }
    return (try? await client.state(.disable, launch: false)) == .notRegistered
  }

  /// `rmdir` only succeeds on an empty directory, which is exactly the rule.
  private func removeEmptyConfigDirectory() {
    rmdir(paths.configDirectory.path)
  }
}
