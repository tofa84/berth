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
                Text(ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: ""))
                    .foregroundStyle(Theme.textTertiary)
                Text("/").foregroundStyle(Theme.textFaint)
                Text(model.selection.title).foregroundStyle(Theme.textSecondary)
            }
            .font(.berthMono(12))
            .lineLimit(1)

            Spacer(minLength: 12)

            searchField

            AccentButton(title: "Run", systemImage: "play.fill") {
                model.showRunSheet = true
            }
        }
        .padding(.leading, 78)   // clear native traffic lights
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Theme.toolbar)
    }

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search containers, images…", text: $model.search)
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
