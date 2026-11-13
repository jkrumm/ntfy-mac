import NtfyAppLogic
import Testing

@MainActor @Suite struct WindowRouterTests {
  @Test func eachRequestIsNewEvenForTheSameWindow() {
    let router = WindowRouter()
    #expect(router.request == nil)
    router.showSettings()
    let first = router.request
    router.showSettings()
    #expect(first?.window == .settings)
    #expect(router.request?.window == .settings)
    #expect(router.request != first)
  }

  @Test func consumingClearsOnlyTheHandledRequest() throws {
    let router = WindowRouter()
    router.showSettings()
    let settings = try #require(router.request)
    router.showOnboarding()
    router.consume(settings)
    #expect(router.request?.window == .onboarding)
    let onboarding = try #require(router.request)
    router.consume(onboarding)
    #expect(router.request == nil)
  }

  @Test func showingHistoryRemembersTheSelectionUntilItIsTaken() {
    let router = WindowRouter()
    let key = MessageKey(topic: "alerts", id: "1")
    router.showHistory(selecting: key)
    #expect(router.request?.window == .history)
    #expect(router.pendingSelection == key)
    router.showHistory()
    #expect(router.pendingSelection == key)
    #expect(router.takeSelection() == key)
    #expect(router.takeSelection() == nil)
  }

  @Test func reopenWithAVisibleWindowOpensNothingNew() {
    let router = WindowRouter()
    #expect(router.reopen(hasVisibleWindows: true))
    #expect(router.request == nil)
  }

  @Test func reopenWithoutAWindowRoutesToHistory() {
    let router = WindowRouter()
    #expect(!router.reopen(hasVisibleWindows: false))
    #expect(router.request?.window == .history)
  }

  @Test func noReopenPathRoutesToSettings() {
    for visible in [true, false] {
      #expect(WindowRouter.reopenDestination(hasVisibleWindows: visible) != .settings)
      let router = WindowRouter()
      _ = router.reopen(hasVisibleWindows: visible)
      #expect(router.request?.window != .settings)
    }
  }
}
