import NtfyAppLogic
import SwiftUI

/// The Settings window: a section list and the section's form. Every control writes at once; the
/// server address and token are the one place with an explicit "Test and save".
struct SettingsWindow: View {
  @Bindable var model: SettingsModel
  @State private var section = SettingsSection.server

  var body: some View {
    NavigationSplitView {
      List(selection: $section) {
        ForEach(SettingsSection.allCases) { section in
          Label(section.title, systemImage: section.symbol).tag(section)
        }
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
    } detail: {
      VStack(spacing: 0) {
        if let notice = model.notice {
          Label(notice, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12))
        }
        detail
      }
      .navigationTitle(section.title)
    }
    .frame(minWidth: 760, minHeight: 500)
    .task { model.start() }
    .onDisappear { model.stop() }
  }

  @ViewBuilder private var detail: some View {
    switch section {
    case .server: SettingsServerSection(model: model)
    case .topics: SettingsTopicsSection(model: model)
    case .sounds: SettingsSoundsSection(model: model)
    case .reAlert: SettingsReAlertSection(model: model)
    case .quietHours: SettingsQuietHoursSection(model: model)
    case .actions: SettingsActionsSection(model: model)
    case .general: SettingsGeneralSection(model: model)
    }
  }
}
