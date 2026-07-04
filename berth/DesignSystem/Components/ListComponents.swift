//
//  ListComponents.swift
//  berth
//
//  Building blocks for the hand-rolled list tables (containers, images,
//  volumes, networks): header/data cells with the shared column-width rules,
//  row icon buttons, the loading placeholder, small tags, the error toast,
//  and the row-delete confirmation dialog.
//

import SwiftUI

// MARK: - Table cells

/// One uppercase column label in a list header. `width == nil` marks the
/// row's flexible column. Right-aligned cells keep a 12 pt gutter inside
/// their fixed frame so digits don't touch the next column (the row HStacks
/// have spacing 0).
struct HeaderCell: View {
    let text: String
    let width: Double?
    var alignment: Alignment = .leading

    init(_ text: String, width: Double?, alignment: Alignment = .leading) {
        self.text = text
        self.width = width
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .font(.berthSans(10, .semibold)).tracking(0.7).foregroundStyle(Theme.textFaint)
            .padding(.trailing, alignment == .trailing ? 12 : 0)
            .frame(width: width.map { CGFloat($0) }, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

/// One fixed-width mono data cell in a list row; same gutter rule as
/// ``HeaderCell``. An optional tooltip carries the untruncated value.
struct MonoCell: View {
    let text: String
    let width: Double
    var alignment: Alignment = .leading
    var help: String?

    init(_ text: String, width: Double, alignment: Alignment = .leading, help: String? = nil) {
        self.text = text
        self.width = width
        self.alignment = alignment
        self.help = help
    }

    var body: some View {
        let cell = Text(text)
            .font(.berthMono(11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            .padding(.trailing, alignment == .trailing ? 12 : 0)
            .frame(width: width, alignment: alignment)
        if let help { cell.help(help) } else { cell }
    }
}

// MARK: - Row icon button

/// 28×28 bordered icon button inside a list row (start/stop, run-from-image).
struct RowIconButton: View {
    let systemImage: String
    var tint: Color = Theme.textSecondary
    var help: String?
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        if let help { button.help(help) } else { button }
    }
}

// MARK: - Loading / toast / tag

/// Centered large spinner while a list makes its first load.
struct LoadingPlaceholder: View {
    var body: some View {
        ProgressView().controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text).lineLimit(2)
        }
        .font(.berthSans(12))
        .foregroundStyle(Theme.red)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.red.opacity(0.3), lineWidth: 1))
        .padding(.bottom, 16)
        .shadow(color: Theme.cardShadow, radius: 12, y: 4)
    }
}

/// Tiny inline marker chip ("ANON", "DEFAULT").
struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.berthMono(9)).foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Row delete confirmation

extension View {
    /// The shared row-delete confirmation: presented while `item` is non-nil;
    /// the destructive button hands the pending value to `action`.
    func deleteConfirmation(
        item: Binding<String?>,
        title: String,
        message: String,
        action: @escaping (String) -> Void
    ) -> some View {
        confirmationDialog(
            title,
            isPresented: Binding(get: { item.wrappedValue != nil },
                                 set: { if !$0 { item.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: item.wrappedValue
        ) { value in
            Button("Delete", role: .destructive) { action(value) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(message)
        }
    }
}
