//
//  FormComponents.swift
//  berth
//
//  Building blocks shared by the Run and Build sheets (and other forms):
//  the sheet header, labeled fields, add-row sections, KEY=VALUE rows, and
//  option toggles.
//

import SwiftUI

/// Sheet title row: accent icon, title, the mirrored CLI command as a mono
/// hint, and a close button.
struct SheetHeader: View {
    let systemImage: String
    let title: String
    let command: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(Theme.accent)
            Text(title).font(.berthSans(16, .semibold)).foregroundStyle(Theme.textPrimary)
            Text(command).font(.berthMono(11)).foregroundStyle(Theme.textFaint)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary).frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}

/// A single labeled form field (dimmed caption above the control).
struct FormField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
            content
        }
    }
}

/// A form section with a caption and a trailing "+ Add" row action.
struct FormSection<Content: View>: View {
    let title: String
    let onAdd: () -> Void
    @ViewBuilder var content: Content

    init(_ title: String, onAdd: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onAdd = onAdd
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionCaption(text: title)
                Spacer()
                Button(action: onAdd) {
                    Text("+ Add").font(.berthSans(11.5, .medium)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            content
        }
    }
}

/// One editable `KEY = value ×` row (env vars, build args, labels).
struct KeyValueFieldRow: View {
    @Binding var pair: KeyValueField
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            FieldText(placeholder: "KEY", text: $pair.key, mono: true)
            Text("=").foregroundStyle(Theme.textFaint)
            FieldText(placeholder: "value", text: $pair.value, mono: true)
            RemoveRowButton(action: onRemove)
        }
    }
}

/// The live `container …` command preview at the bottom of a sheet form.
struct CommandPreviewPanel: View {
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Command")
            Text(command)
                .font(.berthMono(11.5)).foregroundStyle(Theme.greenBright)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.codeBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
    }
}

/// The small × that removes one row from a form list.
struct RemoveRowButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
}

/// A toggleable option chip, labeled with the flag it maps to.
struct OptionToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, _ isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label).font(.berthSans(11.5))
        }
        .toggleStyle(.button)
        .tint(Theme.accent)
    }
}
