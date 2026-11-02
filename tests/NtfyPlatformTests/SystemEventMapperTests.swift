import AppKit
import NtfyCore
import NtfyPlatform
import Testing

@Suite struct SystemEventMapperTests {
  @Test func theFirstPathUpdateIsAlwaysReported() {
    var online = SystemEventMapper()
    #expect(online.pathEvent(satisfied: true) == .pathChanged(online: true))
    var offline = SystemEventMapper()
    #expect(offline.pathEvent(satisfied: false) == .pathChanged(online: false))
  }

  @Test func onlyOnlinenessFlipsAreReported() {
    var mapper = SystemEventMapper()
    _ = mapper.pathEvent(satisfied: true)
    #expect(mapper.pathEvent(satisfied: true) == nil)
    #expect(mapper.pathEvent(satisfied: false) == .pathChanged(online: false))
    #expect(mapper.pathEvent(satisfied: false) == nil)
    #expect(mapper.pathEvent(satisfied: true) == .pathChanged(online: true))
  }

  @Test func workspaceNotificationsMapToWakeAndSleep() {
    #expect(SystemEventMapper.workspaceEvent(named: NSWorkspace.didWakeNotification) == .didWake)
    #expect(
      SystemEventMapper.workspaceEvent(named: NSWorkspace.willSleepNotification) == .willSleep)
    #expect(
      SystemEventMapper.workspaceEvent(named: NSWorkspace.didLaunchApplicationNotification) == nil)
  }
}
