import Foundation
import NtfyClient
import NtfyPlatform

extension CLIEnvironment {
  /// The production wiring: real files, the Keychain, the app socket, the network.
  static func live(
    variables: [String: String] = ProcessInfo.processInfo.environment
  ) -> CLIEnvironment {
    let paths = CLIPaths.live(environment: variables)
    return CLIEnvironment(
      paths: paths,
      variables: variables,
      terminal: Terminal(
        stdinIsTTY: isatty(STDIN_FILENO) != 0, stdoutIsTTY: isatty(STDOUT_FILENO) != 0),
      executablePath: AppBundle.executable()?.path ?? "ntfy-mac",
      config: FileConfigStore(url: paths.configFile),
      secrets: KeychainSecretStore(),
      app: AppLink(socket: paths.socket),
      topicSource: { base, token, allowInsecure in
        NtfyAccountClient(base: base, token: token, allowInsecure: allowInsecure, timeout: 10)
      },
      publisher: { base, token, allowInsecure in
        NtfyPublisher(base: base, token: token, allowInsecure: allowInsecure)
      },
      history: SQLiteHistoryOpener(database: paths.databaseURL),
      clock: SystemClock(),
      runUntilInterrupted: Interrupt.runUntilInterrupted,
      processes: SystemProcessRunner(),
      releases: GitHubReleases(),
      update: SelfUpdatePorts(
        assets: URLSessionReleaseAssetFetcher(), archive: TarArchive(),
        signature: CodesignVerifier(), swapper: AtomicBundleSwapper(),
        restarter: RunningAppRestarter(launch: AppLink.openWithLaunchServices)),
      legacy: .live(
        home: paths.home, stateDirectory: paths.stateDirectory,
        runningExecutable: AppBundle.executable()),
      appCandidates: DuplicateInstall.candidates(home: paths.home),
      prompter: TerminalPrompter(),
      readStandardInput: { FileHandle.standardInput.readDataToEndOfFile() })
  }
}
