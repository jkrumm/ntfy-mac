import Foundation
import NtfyAppLogic
import NtfyClient
import NtfyCore
import NtfyPlatform

/// The composer's publisher: the settings `ntfy-mac publish` resolves (config file, Keychain,
/// environment), read on every send so a changed server or token applies at once.
struct ConfiguredPublisherProvider: PublisherProviding {
  let config: any ConfigStore
  let secrets: any SecretStore

  static func live() -> ConfiguredPublisherProvider {
    ConfiguredPublisherProvider(config: FileConfigStore(), secrets: KeychainSecretStore())
  }

  func resolve() async throws(NtfyError) -> PublisherResolution {
    let stored = try await config.loadChecked()
    let token = try await secrets.token()
    do {
      switch try ConfigResolver.resolve(
        config: stored, keychainToken: token,
        environment: ConfigEnvironment(ProcessInfo.processInfo.environment))
      {
      case .configured(let settings):
        return .ready(
          NtfyPublisher(
            base: settings.url, token: settings.token, allowInsecure: settings.allowInsecure))
      case .notConfigured:
        return .notConfigured
      }
    } catch {
      return .invalid(error.description)
    }
  }
}
