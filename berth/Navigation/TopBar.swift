//
//  TopBar.swift
//  berth
//
//  Full-width custom toolbar (the window uses a hidden title bar, so the native
//  traffic lights float over the leading inset we reserve here).
//

import SwiftUI

struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 14) {
            // Breadcrumb: host / current section
            HStack(spacing: 8) {
                Text(DisplayHost.name)
                    .foregroundStyle(Theme.textTertiary)
                Text("/").foregroundStyle(Theme.textFaint)
                Text(model.selection.title).foregroundStyle(Theme.textSecondary)
            }
            .font(.berthMono(12))
            .lineLimit(1)

            Spacer(minLength: 12)

            if let placeholder = model.selection.searchPlaceholder {
                searchField(placeholder)
            }

            AccentButton(title: "Run", systemImage: "play.fill") {
                model.showRunSheet = true
            }
        }
        // Flush-left, aligned to the sidebar's content edge (12 outer + 8 header
        // inset = 20). The native traffic lights float in the title-bar safe area
        // *above* this bar, so no leading reservation is needed to clear them.
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Theme.toolbar)
    }

    private func searchField(_ placeholder: String) -> some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            TextField(placeholder, text: $model.search)
                .textFieldStyle(.plain)
                .font(.berthSans(12))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 30)
        .background(Theme.fill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
    }
}
