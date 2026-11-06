import AppKit
import NtfyAppLogic
import NtfyCore
import NtfyPlatform
import Sparkle

/// Sparkle behind `UpdateControlling`, for the direct (Developer ID) channel.
///
/// Sparkle only starts when `UpdateEligibility` allows it: a Homebrew copy, a development build
/// (not Developer-ID signed), `NTFY_MAC_NO_SELF_UPDATE=1` and a Team ID that is not the
/// recorded one all leave it off, so those never show a Sparkle error. Scheduled finds are
/// shown as a menu row (gentle reminders), never as a window out of nowhere.
@MainActor
final class SparkleUpdater: NSObject, UpdateControlling {
  /// A probe that has no answer by then fails.
  static let probeTimeout: Duration = .seconds(20)

  let menu: UpdateMenuModel
  private let eligibility: UpdateEligibility
  private var controller: SPUStandardUpdaterController?
  private var latestVersion: String?
  private var probeWaiter: CheckedContinuation<Bool, Never>?

  /// Reads the signature and the recorded Team ID, and records the Team ID of a first signed run.
  init(
    channel: InstallChannel, disabled: Bool, signing: any SigningInspecting,
    pins: any TeamPinStoring, log: @escaping @Sendable (String) -> Void
  ) {
    var recorded: String?
    do throws(NtfyError) {
      recorded = try pins.recorded()
    } catch {
      log("team pin not read: \(error)")
    }
    var eligibility = UpdateEligibility.evaluate(
      channel: channel, disabled: disabled, signing: signing.inspect(), recordedTeam: recorded)
    if eligibility.reason == nil, let team = eligibility.teamToRecord {
      do throws(NtfyError) {
        try pins.record(team)
      } catch {
        // Not recorded means not pinned; updating is not worth that.
        log("team pin not recorded: \(error)")
        eligibility = UpdateEligibility.evaluate(
          channel: channel, disabled: true, signing: eligibility.signing, recordedTeam: recorded)
      }
    }
    self.eligibility = eligibility
    menu = UpdateMenuModel()
    super.init()
    menu.onCheck = { [weak self] in self?.checkInteractively() }
    if let reason = eligibility.reason {
      menu.set(UpdateMenuModel.state(for: reason))
      log("updater off: \(reason.rawValue)")
    }
  }

  /// Starts Sparkle's scheduled checks. Does nothing when updating is not possible.
  func start() {
    guard eligibility.reason == nil, controller == nil else { return }
    controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    menu.set(.ready)
  }

  /// The row's action and `ntfy-mac update`: Sparkle's own window, in front.
  func checkInteractively() {
    guard let controller else { return }
    NSApp.activate()
    controller.updater.checkForUpdates()
  }

  // MARK: UpdateControlling

  nonisolated func status() async -> UpdateStatus { await currentStatus() }

  nonisolated func startInteractive() async -> UpdateStatus {
    await MainActor.run {
      checkInteractively()
      return currentStatus()
    }
  }

  nonisolated func probe() async throws(NtfyError) -> UpdateStatus {
    guard await runProbe() else { throw .serverUnreachable }
    return await currentStatus()
  }

  private func currentStatus() -> UpdateStatus {
    UpdateStatus(
      channel: eligibility.channel, latestVersion: latestVersion,
      updateAvailable: latestVersion != nil, reason: eligibility.reason)
  }

  /// False when the check failed or timed out.
  private func runProbe() async -> Bool {
    guard let updater = controller?.updater, probeWaiter == nil, !updater.sessionInProgress
    else { return true }
    latestVersion = nil
    let timeout = Task {
      try? await Task.sleep(for: Self.probeTimeout)
      finishProbe(succeeded: false)
    }
    let succeeded = await withCheckedContinuation { waiter in
      probeWaiter = waiter
      updater.checkForUpdateInformation()
    }
    timeout.cancel()
    return succeeded
  }

  private func finishProbe(succeeded: Bool) {
    probeWaiter?.resume(returning: succeeded)
    probeWaiter = nil
  }
}

extension SparkleUpdater: SPUUpdaterDelegate {
  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    latestVersion = item.displayVersionString
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    latestVersion = nil
  }

  func updater(
    _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?
  ) {
    let failed = error.map { ($0 as NSError).code != SUError.noUpdateError.rawValue } ?? false
    finishProbe(succeeded: !failed)
  }
}

extension SparkleUpdater: SPUStandardUserDriverDelegate {
  nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

  /// Never in a window of Sparkle's own, not even right after launch: a menu bar app that pops
  /// up at login is not gentle.
  nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
  ) -> Bool {
    false
  }

  nonisolated func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    guard !handleShowingUpdate else { return }
    let version = update.displayVersionString
    Task { @MainActor in
      latestVersion = version
      menu.set(.available(version))
    }
  }

  nonisolated func standardUserDriverWillFinishUpdateSession() {
    Task { @MainActor in
      if eligibility.reason == nil { menu.set(.ready) }
    }
  }
}
