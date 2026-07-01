//
//  EnvList.swift
//  berth
//
//  Environment variables as an aligned key-value list — calmer to read than
//  chips, and a multi-line PATH can't blow up the layout: key dimmed, value
//  bright, one row per variable. Overlong values collapse to a single
//  ellipsized line behind a "more" trigger, so rows stay stable.
//

import SwiftUI

struct EnvList: View {
    let items: [String]
    @State private var expanded: Set<String> = []

    /// Values longer than this collapse behind "more".
    private static let longValue = 60

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 7) {
            ForEach(items, id: \.self) { item in
                let (key, value) = Self.split(item)
                GridRow {
                    Text(key)
                        .font(.berthMono(11)).foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 180, alignment: .leading)
                        .help(key)
                    valueCell(item: item, value: value)
                }
            }
        }
    }

    @ViewBuilder
    private func valueCell(item: String, value: String) -> some View {
        let isLong = value.count > Self.longValue
        let isExpanded = expanded.contains(item)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.berthMono(11.5)).foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(isLong && !isExpanded ? 1 : nil)
                .truncationMode(.tail)
            if isLong {
                Button(isExpanded ? "less" : "more") {
                    if isExpanded { expanded.remove(item) } else { expanded.insert(item) }
                }
                .buttonStyle(.plain)
                .font(.berthSans(10.5, .medium))
                .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Split a `KEY=VALUE` entry at the *first* `=` — values may contain `=`
    /// themselves. Entries without one become a key with an empty value.
    nonisolated static func split(_ entry: String) -> (key: String, value: String) {
        guard let eq = entry.firstIndex(of: "=") else { return (entry, "") }
        return (String(entry[..<eq]), String(entry[entry.index(after: eq)...]))
    }
}
