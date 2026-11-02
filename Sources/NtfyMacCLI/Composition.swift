import Foundation
import NtfyClient
import NtfyCore
import NtfyPlatform
import NtfyStore

/// The CLI's composition root: the one place that picks concrete adapters for the ports.
struct Composition {
  let clock: any NtfyCore.Clock
  let secrets: any SecretStore
  let historyDatabase: URL

  static func live() -> Composition {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
    return Composition(
      clock: SystemClock(),
      secrets: KeychainSecretStore(),
      historyDatabase: StoreLocation.databaseURL(applicationSupport: support)
    )
  }

  func messageStream(base: URL, token: String?) -> any MessageStream {
    URLSessionMessageStream(base: base, token: token)
  }
}
