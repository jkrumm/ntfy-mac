import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The filters, always on screen above the list: priority and date menus and an unread toggle.
/// A control that narrows the list is tinted; below them the scope, the result count and a
/// one-click Clear while anything narrows.
struct HistoryFilterBar: View {
  @Bindable var model: HistoryModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        priority
        date
        unread
        Spacer(minLength: 0)
      }
      HStack(spacing: 6) {
        Text(verbatim: model.scopeTitle)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.middle)
        Text(model.resultCount == 1 ? "1 message" : "\(model.resultCount) messages")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .fixedSize()
        Spacer(minLength: 4)
        if model.isNarrowing {
          Button("Clear") { model.clearNarrowing() }
            .buttonStyle(.link)
            .font(.caption)
            .help("Clear the search and all filters")
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
    .overlay(alignment: .bottom) { Divider() }
  }

  private var priority: some View {
    Menu {
      Picker("Priority", selection: $model.minPriority) {
        Text("Any priority").tag(Priority?.none)
        ForEach([Priority.max, .high, .default, .low], id: \.self) { level in
          Text(Self.menuTitle(level)).tag(Priority?.some(level))
        }
      }
      .pickerStyle(.inline)
    } label: {
      chip(
        model.minPriority.map(Self.chipTitle) ?? "Any priority", symbol: "flag",
        active: model.minPriority != nil)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Filter by priority")
    .accessibilityLabel("Priority filter")
  }

  private var date: some View {
    Menu {
      Picker("Date", selection: $model.dateFilter) {
        ForEach(HistoryDateFilter.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .pickerStyle(.inline)
    } label: {
      chip(
        model.dateFilter.shortTitle, symbol: "calendar", active: model.dateFilter != .all)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Filter by date")
    .accessibilityLabel("Date filter")
  }

  private var unread: some View {
    Button {
      model.unreadOnly.toggle()
    } label: {
      chip("Unread", symbol: "circle.fill", active: model.unreadOnly, menu: false)
    }
    .buttonStyle(.plain)
    .help("Show only unread messages")
    .accessibilityAddTraits(model.unreadOnly ? .isSelected : [])
  }

  private func chip(_ title: String, symbol: String, active: Bool, menu: Bool = true)
    -> some View
  {
    HStack(spacing: 4) {
      Image(systemName: symbol)
        .font(.system(size: menu ? 10 : 6))
      Text(verbatim: title)
      if menu {
        Image(systemName: "chevron.down")
          .font(.system(size: 7, weight: .bold))
          .opacity(0.7)
      }
    }
    .font(.callout)
    .foregroundStyle(active ? Color.accentColor : Color.primary)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(
      active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07),
      in: RoundedRectangle(cornerRadius: 6, style: .continuous)
    )
    .contentShape(Rectangle())
  }

  private static func menuTitle(_ level: Priority) -> String {
    level == .max ? "Urgent only (5)" : "\(level.name) and up (\(level.rawValue)+)"
  }

  private static func chipTitle(_ level: Priority) -> String {
    level == .max ? "Urgent" : "Priority \(level.rawValue)+"
  }
}
