import AppKit
import NtfyAppLogic
import NtfyCore
import SwiftUI

struct SettingsMeetingsSection: View {
  let model: SettingsModel

  var body: some View {
    Form {
      Section {
        Picker(
          settingLabel(.meetingMode),
          selection: Binding(
            get: { model.config.meeting.mode },
            set: { value in Task { await model.setMeetingMode(value) } })
        ) {
          Text("Off").tag(MeetingMode.off)
          Text("Hold notifications").tag(MeetingMode.pause)
        }
        .help(settingCommandHint(.meetingMode))
        Toggle(
          settingLabel(.meetingUrgentBypass),
          isOn: Binding(
            get: { model.config.meeting.urgentBypass },
            set: { value in Task { await model.setMeetingUrgentBypass(value) } })
        )
        .help(settingCommandHint(.meetingUrgentBypass))
        Text("Urgent (priority 5) messages notify even during a meeting.")
          .font(.callout).foregroundStyle(.secondary)
      } footer: {
        Text(
          "While a meeting is going on, banners and sounds are held back. Messages are stored, "
            + "and when the meeting ends they show as one summary."
        )
      }
      Section {
        Toggle(
          settingLabel(.presenting),
          isOn: Binding(
            get: { model.isPresenting },
            set: { value in Task { await model.setPresenting(value) } })
        )
        .help(settingCommandHint(.presenting))
        Text(
          "ntfy-mac cannot tell that you share your screen. Switch this on to hold notifications "
            + "by hand for one hour, whatever the mode above says."
        )
        .font(.callout).foregroundStyle(.secondary)
        Button("Open Notification Settings") {
          if let url = NotificationSettingsLink.displaySharingPane { NSWorkspace.shared.open(url) }
        }
        Text(
          "macOS hides banners by itself while the display is shared or mirrored, unless "
            + "\u{201C}Allow notifications when mirroring or sharing the display\u{201D} is on. "
            + "Turn it off there."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
      Section {
        Text(
          "A meeting is detected when Zoom, Teams, Webex or FaceTime use the microphone, when "
            + "Slack runs a huddle, or when a browser uses the microphone while a camera is on. "
            + "ntfy-mac only learns that audio or a camera is in use. It records nothing, never "
            + "sees what is said or shown, and needs no macOS permission for this. A call muted "
            + "for more than 45 seconds is no longer detected; \u{201C}I am presenting\u{201D} "
            + "covers that."
        )
        .font(.callout).foregroundStyle(.secondary)
      } header: {
        Text("What is detected")
      }
    }
    .formStyle(.grouped)
  }
}
