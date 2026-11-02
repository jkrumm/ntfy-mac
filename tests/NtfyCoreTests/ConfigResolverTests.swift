import Foundation
import Testing

@testable import NtfyCore

@Suite struct ConfigResolverTests {
  private func resolve(
    _ config: Config = Config(), keychain: String? = nil, env: ConfigEnvironment = .init()
  ) throws(ConfigError) -> SettingsResolution {
    try ConfigResolver.resolve(config: config, keychainToken: keychain, environment: env)
  }

  private func settings(
    _ config: Config = Config(), keychain: String? = nil, env: ConfigEnvironment = .init()
  ) throws -> Settings {
    guard case .configured(let settings) = try resolve(config, keychain: keychain, env: env) else {
      throw ConfigError.emptyToken
    }
    return settings
  }

  @Test func missingURLOrTokenIsNotConfigured() throws {
    #expect(try resolve() == .notConfigured)
    #expect(try resolve(Config(url: "https://n.example.com")) == .notConfigured)
    #expect(try resolve(Config(token: "t")) == .notConfigured)
    #expect(try resolve(Config(url: "", token: "")) == .notConfigured)
  }

  @Test func environmentFillsWhatTheFileLacks() throws {
    let env = ConfigEnvironment(url: "https://env.example.com", token: "envtok")
    let result = try settings(env: env)
    #expect(result.url.absoluteString == "https://env.example.com")
    #expect(result.token == "envtok")
  }

  @Test func theFileWinsOverTheEnvironment() throws {
    let env = ConfigEnvironment(url: "https://env.example.com", token: "envtok")
    let result = try settings(Config(url: "https://file.example.com", token: "filetok"), env: env)
    #expect(result.url.absoluteString == "https://file.example.com")
    #expect(result.token == "filetok")
  }

  @Test func tokenPrecedenceIsKeychainThenFileThenEnvironment() throws {
    let config = Config(url: "https://n.example.com", token: "file")
    let env = ConfigEnvironment(token: "env")
    #expect(try settings(config, keychain: "kc", env: env).token == "kc")
    #expect(try settings(config, keychain: nil, env: env).token == "file")
    #expect(try settings(Config(url: "https://n.example.com"), env: env).token == "env")
    #expect(try settings(config, keychain: "", env: env).token == "file")
  }

  @Test func stripsOneTrailingSlash() throws {
    #expect(
      try settings(Config(url: "https://n.example.com/", token: "t")).url.absoluteString
        == "https://n.example.com")
    #expect(
      try settings(Config(url: "https://n.example.com/base/", token: "t")).url.absoluteString
        == "https://n.example.com/base")
  }

  @Test func trimsTheToken() throws {
    #expect(try settings(Config(url: "https://n.example.com", token: "  tok \n")).token == "tok")
  }

  @Test func blankTokenIsAnError() {
    #expect(throws: ConfigError.emptyToken) {
      try resolve(Config(url: "https://n.example.com", token: "   "))
    }
  }

  @Test func rejectsOtherSchemes() {
    #expect(throws: ConfigError.unsupportedScheme("ftp:")) {
      try resolve(Config(url: "ftp://bad.host", token: "t"))
    }
  }

  @Test(arguments: ["not a url at all", "https://", "://x", "example.com"])
  func rejectsUnparseableURLs(url: String) {
    #expect(throws: ConfigError.self) { try resolve(Config(url: url, token: "t")) }
  }

  @Test func errorsNameTheProblem() {
    #expect(ConfigError.invalidURL("x").description == "Invalid NTFY URL: x")
    #expect(ConfigError.unsupportedScheme("ftp:").description.contains("Must be http or https"))
    #expect(ConfigError.emptyToken.description == "NTFY token must not be empty.")
  }

  @Test func topicsOverrideParsing() throws {
    #expect(ConfigResolver.topics(from: "a,b,c") == ["a", "b", "c"])
    #expect(ConfigResolver.topics(from: " a , b ") == ["a", "b"])
    #expect(ConfigResolver.topics(from: "a,,b,") == ["a", "b"])
    #expect(ConfigResolver.topics(from: nil) == nil)
    #expect(ConfigResolver.topics(from: "") == nil)
    #expect(ConfigResolver.topics(from: ",") == [])
  }

  @Test func topicsOverrideAndExtrasReachTheSettings() throws {
    let config = Config(
      url: "https://n.example.com", token: "t", sounds: [1: .silent], dismiss: [2: 9],
      extraTopics: ["x"])
    let result = try settings(config, env: ConfigEnvironment(topics: "a, b"))
    #expect(result.topics == ["a", "b"])
    #expect(result.extraTopics == ["x"])
    #expect(result.sounds == [1: .silent])
    #expect(result.dismiss == [2: 9])
    #expect(try settings(config).topics == nil)
  }

  @Test func readsTheProcessEnvironmentKeys() {
    let env = ConfigEnvironment([
      "NTFY_URL": "u", "NTFY_TOKEN": "t", "NTFY_TOPICS": "a", "NTFY_DEBUG": "1",
    ])
    #expect(env == ConfigEnvironment(url: "u", token: "t", topics: "a"))
  }

  @Test func allowInsecureReachesTheSettings() throws {
    let insecure = Config(url: "http://n.example.com", token: "t", allowInsecure: true)
    #expect(try settings(insecure).allowInsecure)
    #expect(try settings(Config(url: "http://n.example.com", token: "t")).allowInsecure == false)
  }
}
