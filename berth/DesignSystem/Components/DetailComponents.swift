//
//  DetailComponents.swift
//  berth
//
//  Building blocks shared by the detail views (container, image) and the
//  System/Builds cards: back navigation, the underlined tab strip, key-value
//  info cards, and the Inspect JSON panel.
//

import SwiftUI

// MARK: - Back button (detail header)

struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left").font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary).frame(width: 30, height: 30)
                .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab strip (detail views)

/// The underlined tab row under a detail header. `Tab` is the screen's own
/// tab enum; its raw value is the label.
struct DetailTabBar<Tab: Hashable & RawRepresentable>: View where Tab.RawValue == String {
    let tabs: [Tab]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs, id: \.self) { tab in
                let active = tab == selection
                Text(tab.rawValue)
                    .font(.berthSans(12.5, active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        if active { Rectangle().fill(Theme.accent).frame(height: 2) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = tab }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

// MARK: - Info card (key-value list)

struct InfoCard<Content: View>: View {
    let title: String
    /// Stretch to fill the row height so paired cards stay the same size.
    var fill: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        Card(fill: fill) {
            VStack(alignment: .leading, spacing: 12) {
                SectionCaption(text: title)
                // Hairlines between the rows make the key/value list scannable;
                // single-child cards (e.g. Environment) get none.
                VStack(alignment: .leading, spacing: 0) {
                    Group(subviews: content) { subviews in
                        ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                            if index > 0 { Divider().overlay(Theme.border).padding(.vertical, 5.5) }
                            subview
                        }
                    }
                }
            }
        }
    }
}

struct KeyValue: View {
    let key: String
    let value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }

    var body: some View {
        // Fixed label column with the value right next to it — the eye never
        // has to jump across the card to find a short value.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).font(.berthSans(12.5)).foregroundStyle(Theme.textTertiary)
                .frame(width: 96, alignment: .leading)
            Text(value).font(.berthMono(12)).foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Code panel chrome + Inspect

extension View {
    /// Inset "code" chrome shared by the logs, inspect, and build-output
    /// panels: codeBg surface, rounded corners, hairline border.
    func codePanel() -> some View {
        background(Theme.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border, lineWidth: 1))
    }
}

/// The Inspect tab's panel: pretty-printed JSON in a horizontally scrollable,
/// selectable mono block.
struct InspectPanel: View {
    let json: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(json)
                .font(.berthMono(11.5)).foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled).padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 460)
        .codePanel()
    }
}
