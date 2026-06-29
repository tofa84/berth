//
//  Charts.swift
//  berth
//
//  Lightweight bar chart + donut gauge (no Charts framework dependency).
//

import SwiftUI

/// A row of bottom-aligned bars. `values` are normalized 0...1.
struct BarChart: View {
    let values: [Double]
    var color: Color = Theme.accent
    var height: CGFloat = 62
    var slots: Int = 40

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<slots, id: \.self) { i in
                let v = value(at: i)
                RoundedRectangle(cornerRadius: 2)
                    .fill(v == nil ? Theme.fill : color)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, CGFloat(v ?? 0) * height))
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    /// Right-align the samples so new data grows in from the right.
    private func value(at index: Int) -> Double? {
        let offset = slots - values.count
        let idx = index - offset
        guard idx >= 0, idx < values.count else { return nil }
        return min(1, max(0, values[idx]))
    }
}

struct DonutGauge: View {
    let fraction: Double      // 0...1
    let label: String
    let detail: String
    var color: Color = Theme.accent

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, max(0, fraction)))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Format.percent(fraction))
                    .font(.berthMono(18, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 88, height: 88)
            VStack(spacing: 2) {
                Text(label).font(.berthSans(12, .medium)).foregroundStyle(Theme.textSecondary)
                Text(detail).font(.berthMono(10.5)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Compact metric tile (label + big mono value).
struct MetricTile: View {
    let label: String
    let value: String
    var accent: Color = Theme.textPrimary
    var footnote: String? = nil

    var body: some View {
        Card(padding: 15) {
            VStack(alignment: .leading, spacing: 8) {
                SectionCaption(text: label)
                Text(value).font(.berthMono(22, .semibold)).foregroundStyle(accent)
                if let footnote {
                    Text(footnote).font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}
