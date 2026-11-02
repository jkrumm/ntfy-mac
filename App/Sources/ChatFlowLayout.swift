import SwiftUI

/// Lays children out in rows, wrapping at the proposed width. For the tag chips of a bubble.
struct ChatFlowLayout: Layout {
  var spacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrange(in: proposal.width ?? .infinity, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let layout = arrange(in: bounds.width, subviews: subviews)
    for (subview, origin) in zip(subviews, layout.origins) {
      subview.place(
        at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
    }
  }

  private func arrange(in width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize)
  {
    var origins: [CGPoint] = []
    var column: CGFloat = 0
    var row: CGFloat = 0
    var rowHeight: CGFloat = 0
    var widest: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if column > 0, column + size.width > width {
        column = 0
        row += rowHeight + spacing
        rowHeight = 0
      }
      origins.append(CGPoint(x: column, y: row))
      column += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      widest = max(widest, column - spacing)
    }
    return (origins, CGSize(width: widest, height: row + rowHeight))
  }
}
