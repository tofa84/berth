//
//  FlowLayout.swift
//  berth
//
//  A simple wrapping (flow) layout + a convenience wrapper for chip rows.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    // Clamp each item to the available width so an item wider than the row (e.g. a
    // long `PATH=…` env chip) wraps onto multiple lines instead of overflowing and
    // getting clipped by the enclosing card.
    private func fittedSize(_ s: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = s.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth else { return ideal }
        return s.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = fittedSize(s, maxWidth: maxWidth)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = fittedSize(s, maxWidth: bounds.width)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct FlexibleWrap<Item, ItemView: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> ItemView

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                content(item)
            }
        }
    }
}
