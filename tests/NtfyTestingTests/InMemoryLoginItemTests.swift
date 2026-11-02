import NtfyCore
import NtfyTesting
import Testing

@Suite struct InMemoryLoginItemTests {
  @Test func registeringAndUnregisteringMoveTheState() {
    let item = InMemoryLoginItem()
    #expect(item.state() == .notRegistered)
    #expect(item.setEnabled(true) == .enabled)
    #expect(item.state().isEnabled)
    #expect(item.setEnabled(false) == .notRegistered)
  }

  @Test func approvalCanBeRequired() {
    let item = InMemoryLoginItem(requiresApproval: true)
    #expect(item.setEnabled(true) == .requiresApproval)
    #expect(!item.state().isEnabled)
  }
}
