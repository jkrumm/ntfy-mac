import NtfyAppLogic
import NtfyCore
import Testing

@MainActor
@Suite struct UpdateMenuModelTests {
  @Test func aDevelopmentBuildShowsNoRowAndTheOthersExplainThemselves() {
    #expect(UpdateMenuModel.state(for: .unsigned) == .hidden)
    for reason in [UpdateUnavailableReason.homebrew, .disabled, .teamMismatch] {
      guard case .blocked(let text) = UpdateMenuModel.state(for: reason) else {
        Issue.record("\(reason) should be blocked")
        continue
      }
      #expect(!text.isEmpty)
    }
  }

  @Test func theRowRunsTheUpdaterAction() {
    var checks = 0
    let model = UpdateMenuModel(state: .ready, onCheck: { checks += 1 })
    model.check()
    model.set(.available("2.1.0"))
    model.check()
    #expect(checks == 2 && model.state == .available("2.1.0"))
  }
}
