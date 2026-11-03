import NtfyAppLogic
import NtfyCore
import Testing

@MainActor @Suite struct ReAlertSummaryTests {
  @Test func theDefaultNamesUrgentOnlyAndSaysLowerPrioritiesNeverRepeat() async {
    let rig = SettingsRig()
    await rig.model.setReAlert(true)
    let text = rig.model.reAlertSummary
    #expect(text.contains("Only urgent (priority 5)"))
    #expect(text.contains("every 5 minutes"))
    #expect(text.contains("up to 12 times"))
    #expect(text.contains("Lower priorities never re-alert"))
  }

  @Test func aLowerMinimumNamesItsPriorityAndTheDefaultOneCanBeIncluded() async {
    let rig = SettingsRig()
    await rig.model.setReAlertMinPriority(3)
    await rig.model.setReAlertInterval(seconds: 90)
    await rig.model.setReAlertMaxRepeats(1)
    let text = rig.model.reAlertSummary
    #expect(text.contains("priority 3 (default) or higher"))
    #expect(text.contains("every 90 seconds"))
    #expect(text.contains("up to once"))
  }

  @Test func switchedOffEveryMessageNotifiesOnce() async {
    let rig = SettingsRig()
    await rig.model.setReAlert(false)
    #expect(rig.model.reAlertSummary.contains("notifies once"))
  }
}
