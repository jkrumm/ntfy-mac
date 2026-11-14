import Foundation
import NtfyCore
import NtfyIPC
import NtfyPlatform
import NtfyStore

/// The health checks, in the order they are reported. Everything here only reads; the one write
/// is the opt-in test notification.
struct DoctorChecks {
  let environment: CLIEnvironment

  func run(sendTest: Bool) async -> [DoctorCheck] {
    var checks: [DoctorCheck] = []
    let loaded = await loadConfig()
    checks.append(configCheck(loaded))
    checks.append(await tokenCheck(loaded))
    checks += await serverChecks()
    let app = await appChecks()
    checks += app
    checks.append(await historyCheck())
    checks.append(await legacyCheck())
    checks.append(duplicateCheck())
    checks.append(updateCheck())
    checks.append(timeSensitiveCheck())
    if case .success(let config) = loaded { checks.append(overridesCheck(config)) }
    if sendTest { checks.append(await testNotification(appIsUp: app.first?.status != .fail)) }
    return checks
  }

  // MARK: Config

  private func loadConfig() async -> Result<Config, NtfyError> {
    do throws(NtfyError) {
      return .success(try await environment.config.loadChecked())
    } catch {
      return .failure(error)
    }
  }

  private func configCheck(_ loaded: Result<Config, NtfyError>) -> DoctorCheck {
    switch loaded {
    case .failure(let error):
      return .failure("config", error, "Config file unreadable")
    case .success(let config):
      let url = config.url ?? environment.variables["NTFY_URL"]
      guard let url, !url.isEmpty else {
        return DoctorCheck("config", .fail, "No server configured", detail: "Run: ntfy-mac setup")
      }
      return DoctorCheck("config", .passed, "Server: \(url)")
    }
  }

  private func tokenCheck(_ loaded: Result<Config, NtfyError>) async -> DoctorCheck {
    let keychain: String?
    do throws(NtfyError) {
      keychain = try await environment.secrets.token()
    } catch {
      return .failure("token", error, "Cannot read the Keychain")
    }
    if keychain?.isEmpty == false { return DoctorCheck("token", .passed, "Token in the Keychain") }
    if case .success(let config) = loaded, config.token?.isEmpty == false {
      return DoctorCheck(
        "token", .warn, "Token still in config.json",
        detail: "The app moves it to the Keychain when it starts")
    }
    if environment.variables["NTFY_TOKEN"]?.isEmpty == false {
      return DoctorCheck("token", .warn, "Token from NTFY_TOKEN")
    }
    return DoctorCheck("token", .fail, "No token", detail: "Run: ntfy-mac setup")
  }

  // MARK: Server

  private func serverChecks() async -> [DoctorCheck] {
    let settings: Settings
    do {
      settings = try await environment.settings()
    } catch {
      let skipped = "Skipped (not configured)"
      return ["server", "auth", "topics"].map { DoctorCheck($0, .skipped, skipped) }
    }
    let source = environment.topicSource(settings.url, settings.token, settings.allowInsecure)
    do throws(NtfyError) {
      let discovered = try await source.subscribedTopics()
      return [
        DoctorCheck("server", .passed, "Server reachable"),
        DoctorCheck("auth", .passed, "Token accepted"),
        topicsCheck(settings, discovered: discovered),
      ]
    } catch {
      return serverFailure(error)
    }
  }

  private func serverFailure(_ error: NtfyError) -> [DoctorCheck] {
    switch error {
    case .unauthorized:
      return [
        DoctorCheck("server", .passed, "Server reachable"),
        DoctorCheck(
          "auth", .fail, "Authentication failed", detail: "Run: ntfy-mac setup", exit: .auth),
        DoctorCheck("topics", .skipped, "Skipped (not authenticated)"),
      ]
    default:
      return [
        .failure("server", error, "Cannot use the server"),
        DoctorCheck("auth", .skipped, "Skipped (server check failed)"),
        DoctorCheck("topics", .skipped, "Skipped (server check failed)"),
      ]
    }
  }

  private func topicsCheck(_ settings: Settings, discovered: [String]) -> DoctorCheck {
    let resolved = TopicResolver.resolve(
      selection: TopicSelection(override: settings.topics, extra: settings.extraTopics),
      discovered: discovered)
    if !resolved.invalid.isEmpty {
      return DoctorCheck(
        "topics", .warn, "Invalid topic names: \(resolved.invalid.joined(separator: ", "))")
    }
    guard !resolved.topics.isEmpty else {
      return DoctorCheck(
        "topics", .warn, "No subscribed topics", detail: "Subscribe via: ntfy-mac subscribe <topic>"
      )
    }
    let local = settings.extraTopics.isEmpty ? "" : " (+\(settings.extraTopics.count) local)"
    return DoctorCheck(
      "topics", .passed,
      "\(resolved.topics.count) topic(s)\(local): \(resolved.topics.joined(separator: ", "))")
  }

  // MARK: App

  /// Asks a running app; never launches one.
  private func ask(_ command: Command) async throws(NtfyError) -> Response {
    try await environment.app.send(Request(id: UUID().uuidString, command: command), launch: false)
  }

  private func appChecks() async -> [DoctorCheck] {
    let status: Response
    do throws(NtfyError) {
      status = try await ask(.status)
    } catch {
      return [
        DoctorCheck(
          "app", .fail, "The app is not running", detail: "Start it with: ntfy-mac start",
          exit: .appUnavailable),
        DoctorCheck("permissions", .skipped, "Skipped (app not running)"),
        DoctorCheck("login-item", .skipped, "Skipped (app not running)"),
      ]
    }
    return [appCheck(status), await permissionCheck(), await loginItemCheck()]
  }

  private func loginItemCheck() async -> DoctorCheck {
    do {
      switch try await LoginItemClient(app: environment.app).state(launch: false) {
      case .enabled:
        return DoctorCheck("login-item", .passed, "Starts at login")
      case .requiresApproval:
        return DoctorCheck(
          "login-item", .warn, "Login item needs approval",
          detail: "Approve it in System Settings > General > Login Items")
      case .notRegistered, .notFound:
        return DoctorCheck(
          "login-item", .warn, "Does not start at login",
          detail: "Enable with: ntfy-mac login-item on")
      }
    } catch {
      return DoctorCheck(
        "login-item", .warn, "Could not read the login item", detail: ErrorReport(error).message)
    }
  }

  private func appCheck(_ response: Response) -> DoctorCheck {
    guard response.status == .success, let info = response.result?.status else {
      return DoctorCheck("app", .fail, response.message ?? "The app answered with an error")
    }
    var detail: String?
    if let until = info.pausedUntil { detail = "Paused until \(until.formatted())" }
    if info.appVersion != Version.current {
      return DoctorCheck(
        "app", .warn, "App \(info.appVersion) differs from CLI \(Version.current)",
        detail: detail ?? "Update both to the same version")
    }
    return DoctorCheck(
      "app", .passed, "Running (\(info.appVersion), \(info.connection))", detail: detail)
  }

  private func permissionCheck() async -> DoctorCheck {
    let response: Response
    do throws(NtfyError) {
      response = try await ask(.permission)
    } catch {
      return .failure("permissions", error, "Could not ask the app")
    }
    guard let summary = response.result?.permission else {
      return DoctorCheck("permissions", .fail, response.message ?? "No permission state reported")
    }
    let hints = summary.problems.map(\.hint).joined(separator: "; ")
    if !summary.usable {
      return DoctorCheck(
        "permissions", .fail, "Notifications are not usable", detail: hints, exit: .appUnavailable)
    }
    if !summary.problems.isEmpty {
      return DoctorCheck("permissions", .warn, "Notifications allowed, with caveats", detail: hints)
    }
    return DoctorCheck("permissions", .passed, "Notifications allowed")
  }

  private func testNotification(appIsUp: Bool) async -> DoctorCheck {
    guard appIsUp else { return DoctorCheck("test", .skipped, "Skipped (app not running)") }
    let payload = NotifyPayload(title: "ntfy-mac doctor", body: "Test notification")
    do throws(NtfyError) {
      let response = try await environment.app.send(
        Request(id: UUID().uuidString, command: .notify, notify: payload), launch: false)
      guard response.status == .success else {
        let denied = response.code == .permissionDenied
        return DoctorCheck(
          "test", .fail, response.message ?? "The app could not post",
          exit: denied ? .appUnavailable : .runtime)
      }
      return DoctorCheck("test", .passed, "Test notification posted")
    } catch {
      return .failure("test", error, "Could not reach the app")
    }
  }

  // MARK: History and settings

  private func historyCheck() async -> DoctorCheck {
    let database = environment.paths.databaseURL
    guard FileManager.default.fileExists(atPath: database.path) else {
      return DoctorCheck("history", .warn, "No history database yet (created by the app)")
    }
    do throws(NtfyError) {
      guard let server = try await environment.historyServer() else {
        return DoctorCheck("history", .warn, "No server configured, history not checked")
      }
      let store = try SQLiteHistoryStore.openReadOnly(
        at: database, server: server, clock: SystemClock())
      defer { try? store.close() }
      let last = try await store.lastMessageID()
      return DoctorCheck("history", .passed, "Readable, last message: \(last ?? "(none)")")
    } catch {
      return .failure("history", error, "History database unreadable")
    }
  }

  /// Read-only and quick: no Launch Services scan. `ntfy-mac migrate --dry-run` does the full one.
  private func legacyCheck() async -> DoctorCheck {
    let report = await environment.legacy.detect(scope: .quick)
    let kegs = environment.legacy.homebrewV1Kegs()
    guard !report.found.isEmpty || !kegs.isEmpty else {
      return DoctorCheck("legacy-install", .passed, "No 1.x leftovers")
    }
    var details: [String] = []
    if !report.found.isEmpty { details.append("Remove the leftovers with: ntfy-mac migrate") }
    if !kegs.isEmpty {
      details.append(
        "The 1.x binary is still on PATH via Homebrew: run `brew uninstall ntfy-mac` "
          + "(config and history stay), then install 2.0 per the README")
    }
    let summary =
      report.found.isEmpty
      ? "Homebrew still has the 1.x ntfy-mac"
      : "\(report.found.count) leftover(s) of a 1.x install"
    return DoctorCheck(
      "legacy-install", .warn, summary, detail: details.joined(separator: ". "))
  }

  private func duplicateCheck() -> DoctorCheck {
    DuplicateInstall.check(
      candidates: environment.appCandidates, runningExecutable: environment.executablePath)
  }

  private func overridesCheck(_ config: Config) -> DoctorCheck {
    let sounds = config.sounds.count
    let dismiss = config.dismiss.count
    guard sounds + dismiss > 0 else { return DoctorCheck("overrides", .passed, "Using defaults") }
    return DoctorCheck(
      "overrides", .passed, "\(sounds) custom sound(s), \(dismiss) custom dismiss time(s)",
      detail: "View with: ntfy-mac config")
  }
}
