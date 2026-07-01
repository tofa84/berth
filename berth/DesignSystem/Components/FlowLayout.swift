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
        let sizes = subviews.map { fittedSize($0, maxWidth: maxWidth) }
        let laid = Self.arrange(sizes: sizes, maxWidth: maxWidth, spacing: spacing)
        return CGSize(width: proposal.width ?? laid.size.width, height: laid.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { fittedSize($0, maxWidth: bounds.width) }
        let laid = Self.arrange(sizes: sizes, maxWidth: bounds.width, spacing: spacing)
        for (i, s) in subviews.enumerated() {
            let p = laid.positions[i]
            s.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y),
                    anchor: .topLeading, proposal: ProposedViewSize(sizes[i]))
        }
    }

    /// Pure flow math: lays `sizes` left-to-right, wrapping to a new row when the
    /// next item would exceed `maxWidth` (the first item in a row never wraps).
    /// Returns each item's top-leading position (origin‑relative) and the total
    /// content size — `height` is the summed row heights + inter‑row spacing.
    nonisolated static func arrange(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat)
        -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        positions.reserveCapacity(sizes.count)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, contentWidth: CGFloat = 0
        for size in sizes {
            if x + size.width > maxWidth && x > 0 {
                contentWidth = max(contentWidth, x - spacing)
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        contentWidth = max(contentWidth, x > 0 ? x - spacing : 0)
        return (positions, CGSize(width: contentWidth, height: y + rowHeight))
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
