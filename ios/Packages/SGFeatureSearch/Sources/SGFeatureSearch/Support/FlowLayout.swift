import SwiftUI

struct SearchFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if shouldWrap(x: x, itemWidth: size.width, width: width) {
                maxWidth = max(maxWidth, x)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            if x > 0 {
                x += spacing
            }
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
        maxWidth = max(maxWidth, x)
        return CGSize(width: width.isFinite ? width : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if shouldWrap(
                x: x - bounds.minX,
                itemWidth: size.width,
                width: bounds.width
            ) {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            if x > bounds.minX {
                x += spacing
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func shouldWrap(x: CGFloat, itemWidth: CGFloat, width: CGFloat) -> Bool {
        x > 0 && x + spacing + itemWidth > width
    }
}
