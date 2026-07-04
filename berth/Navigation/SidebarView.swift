//
//  SidebarView.swift
//  berth
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 16)

            ForEach(SidebarSection.allCases, id: \.self) { section in
                SectionCaption(text: section.rawValue)
                    .padding(.horizontal, 8)
                    .padding(.top, section == .system ? 16 : 8)
                    .padding(.bottom, 6)
                ForEach(SidebarItem.items(in: section)) { item in
                    row(item)
                }
            }

            Spacer(minLength: 12)
            statusCard
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }

    // MARK: Header (logo + version)

    private var header: some View {
        HStack(spacing: 10) {
            LogoMark()
                .frame(width: 26, height: 26)
            Text("berth")
                .font(.berthMono(16, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(Self.appVersion)
                .font(.berthMono(9.5))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.fill)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    /// The app's own marketing version (CFBundleShortVersionString), e.g. "1.1.0".
    /// The engine/apiserver version lives on the System screen, not here.
    private static let appVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

    // MARK: Nav row

    private func row(_ item: SidebarItem) -> some View {
        let active = model.selection == item
        return Button {
            model.selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .frame(width: 16)
                    .foregroundStyle(active ? Theme.accent : Theme.textTertiary)
                Text(item.title)
                    .font(.berthSans(13))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
                if let count = model.counts[item] {
                    CountBadge(text: "\(count)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(active ? Theme.fill : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) {
                if active {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .offset(x: -4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Engine status card

    private var statusCard: some View {
        let running = model.engine.isRunning
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                StatusDot(color: running ? Theme.green : Theme.red, pulse: running)
                Text("API server")
                    .font(.berthSans(12, .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(running ? "running" : "stopped")
                    .font(.berthMono(11))
                    .foregroundStyle(running ? Theme.green : Theme.red)
            }
            // Host name and machine spec stack vertically so the (often long)
            // host name gets the card's full width instead of being clipped.
            VStack(alignment: .leading, spacing: 2) {
                Text(hostName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(hostName)
                Text(machineSummary)
            }
            .font(.berthMono(11))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(Theme.cardAlt)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }

    /// Local host name (masked by ``DisplayHost.placeholder`` when set).
    private var hostName: String { DisplayHost.name }

    private var machineSummary: String {
        "\(HostInfo.cores)C · \(HostInfo.memoryGB) GB"
    }
}

/// The orange rounded-square "berth" mark with three vertical bars (a dock/berth).
struct LogoMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(LinearGradient(colors: [Color(hex: 0xF3AE4E), Color(hex: 0xE2872B)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color(hex: 0x281400).opacity(0.38)).frame(width: 1.5)
                    }
                }
                .padding(.vertical, 5)
            }
            .shadow(color: Color(hex: 0xE2872B).opacity(0.4), radius: 3, y: 2)
    }
}
