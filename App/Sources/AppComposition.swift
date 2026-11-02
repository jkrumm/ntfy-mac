import Foundation
import NtfyClient
import NtfyCore
import NtfyPlatform
import NtfyStore

/// The app's composition root: the one place that picks concrete adapters for the ports.
struct AppComposition {
  let clock: any NtfyCore.Clock
  let secrets: any SecretStore
  let historyDatabase: URL

  static func live() -> AppComposition {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
    return AppComposition(
      clock: SystemClock(),
      secrets: KeychainSecretStore(),
      historyDatabase: StoreLocation.databaseURL(applicationSupport: support)
    )
  }

  func messageStream(base: URL, token: String?) -> any MessageStream {
    URLSessionMessageStream(base: base, token: token)
  }
}
