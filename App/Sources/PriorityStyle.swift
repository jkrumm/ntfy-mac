import NtfyCore
import SwiftUI

/// How a priority shows: a symbol and a word as well as a colour, so colour is never the only cue.
extension Priority {
  /// Nil for the default priority, which needs no marker.
  var symbol: String? {
    switch rawValue {
    case 5: "exclamationmark.3"
    case 4: "exclamationmark.2"
    case 2: "arrow.down"
    case 1: "arrow.down.to.line"
    default: nil
    }
  }

  var name: String {
    switch rawValue {
    case 5: "Urgent"
    case 4: "High"
    case 3: "Default"
    case 2: "Low"
    default: "Min"
    }
  }

  var tint: Color {
    switch rawValue {
    case 5: .red
    case 4: .orange
    default: .secondary
    }
  }
}

/// The marker in a list row or the detail header; nothing for the default priority.
struct PriorityMarker: View {
  let priority: Priority

  var body: some View {
    if let symbol = priority.symbol {
      Image(systemName: symbol)
        .foregroundStyle(priority.tint)
        .help("\(priority.name) priority")
        .accessibilityLabel("\(priority.name) priority")
    }
  }
}
