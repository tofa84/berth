//
//  Components.swift
//  berth
//
//  Small reusable building blocks shared across screens.
//

import SwiftUI

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Section caption (UPPERCASE label)

struct SectionCaption: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.berthSans(10.5, .semibold))
            .tracking(1.0)
            .foregroundStyle(Theme.textMuted)
    }
}

// MARK: - Status dot

struct StatusDot: View {
    var color: Color
    var pulse: Bool = false
    var size: CGFloat = 8
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulse && on ? 0.3 : 1)
            .animation(pulse ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : nil, value: on)
            .onAppear { if pulse { on = true } }
    }
}

// MARK: - Pill / Badge

struct CountBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.berthMono(10))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A segmented pill control (e.g. All / Running / Stopped).
struct SegmentedPills<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { opt in
                let active = opt.value == selection
                Text(opt.label)
                    .font(.berthSans(11.5, active ? .medium : .regular))
                    .foregroundStyle(active ? Theme.onAccent : Theme.textTertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(active ? Theme.accent : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = opt.value }
            }
        }
        .padding(3)
        .background(Theme.cardAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
    }
}

// MARK: - Secondary / accent buttons (design-styled)

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.berthSans(12))
            .foregroundStyle(role == .destructive ? Theme.red : Theme.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(role == .destructive ? Theme.red.opacity(0.10) : Theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(role == .destructive ? Theme.red.opacity(0.25) : Theme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct AccentButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.berthSans(12.5, .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-screen states

struct CenteredMessage: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(Theme.textMuted)
            Text(title)
                .font(.berthSans(17, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.berthSans(12.5))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                AccentButton(title: actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

/// Standard screen header (title + subtitle on the left, trailing controls).
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.berthSans(20, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.berthSans(12.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Form controls

struct FieldText: View {
    let placeholder: String
    @Binding var text: String
    var mono: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? .berthMono(12.5) : .berthSans(13))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
    }
}

/// A modal scaffold: title, content, Cancel + confirm buttons.
struct SheetScaffold<Content: View>: View {
    let title: String
    var confirmTitle: String = "Create"
    var confirmDisabled: Bool = false
    @ViewBuilder var content: Content
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.berthSans(16, .semibold)).foregroundStyle(Theme.textPrimary)
            content
            HStack {
                Spacer()
                SecondaryButton(title: "Cancel") { dismiss() }
                Button(action: confirm) {
                    Text(confirmTitle)
                        .font(.berthSans(12.5, .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(confirmDisabled)
                .opacity(confirmDisabled ? 0.5 : 1)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.bg)
    }
}
