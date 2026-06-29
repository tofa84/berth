//
//  RunContainerSheet.swift
//  berth
//

import SwiftUI

struct RunContainerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var form = RunFormModel()

    var body: some View {
        @Bindable var form = form
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identitySection(form)
                    envSection(form)
                    portsSection(form)
                    resourcesSection(form)
                    optionsSection(form)
                    previewSection(form)
                }
                .padding(20)
            }
            Divider().overlay(Theme.border)
            footer(form)
        }
        .frame(width: 580, height: 620)
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill").foregroundStyle(Theme.accent)
            Text("Run a container").font(.berthSans(16, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("container run").font(.berthMono(11)).foregroundStyle(Theme.textFaint)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(Theme.textTertiary).frame(width: 26, height: 26)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func identitySection(_ form: RunFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                labeled("Image") { FieldText(placeholder: "nginx:latest", text: $form.image, mono: true) }
                labeled("Name") { FieldText(placeholder: "optional", text: $form.name) }.frame(width: 180)
            }
            labeled("Platform") {
                Picker("", selection: $form.arch) {
                    Text("linux/arm64").tag("arm64")
                    Text("linux/amd64").tag("amd64")
                }
                .labelsHidden().pickerStyle(.menu).tint(Theme.textSecondary).frame(width: 180)
            }
        }
    }

    private func envSection(_ form: RunFormModel) -> some View {
        @Bindable var form = form
        return section("Environment", add: { form.addEnv() }) {
            ForEach($form.env) { $e in
                HStack(spacing: 8) {
                    FieldText(placeholder: "KEY", text: $e.key, mono: true)
                    Text("=").foregroundStyle(Theme.textFaint)
                    FieldText(placeholder: "value", text: $e.value, mono: true)
                    removeButton { form.env.removeAll { $0.id == e.id } }
                }
            }
        }
    }

    private func portsSection(_ form: RunFormModel) -> some View {
        @Bindable var form = form
        return section("Published ports", add: { form.addPort() }) {
            ForEach($form.ports) { $p in
                HStack(spacing: 8) {
                    FieldText(placeholder: "8080", text: $p.host, mono: true)
                    Text(":").foregroundStyle(Theme.textFaint)
                    FieldText(placeholder: "80", text: $p.container, mono: true)
                    Toggle("UDP", isOn: $p.udp).toggleStyle(.button).font(.berthSans(11))
                    removeButton { form.ports.removeAll { $0.id == p.id } }
                }
            }
        }
    }

    private func resourcesSection(_ form: RunFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            SectionCaption(text: "Resources")
            HStack(spacing: 24) {
                Stepper(value: $form.cpus, in: 1...32) {
                    Text("\(form.cpus) CPU").font(.berthSans(12.5)).foregroundStyle(Theme.textSecondary)
                }
                Stepper(value: $form.memoryGB, in: 1...128) {
                    Text("\(form.memoryGB) GB memory").font(.berthSans(12.5)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func optionsSection(_ form: RunFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            SectionCaption(text: "Options")
            FlowLayout(spacing: 10) {
                optionToggle("Remove on exit --rm", $form.remove)
                optionToggle("Read-only", $form.readOnly)
                optionToggle("Rosetta", $form.rosetta)
            }
            Text("Runs detached — follow output in the container's Logs tab.")
                .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
        }
    }

    private func previewSection(_ form: RunFormModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Command")
            Text(form.commandPreview)
                .font(.berthMono(11.5)).foregroundStyle(Theme.greenBright)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.codeBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func footer(_ form: RunFormModel) -> some View {
        HStack {
            if let e = form.error {
                Text(e).font(.berthSans(11.5)).foregroundStyle(Theme.red).lineLimit(2)
            }
            Spacer()
            SecondaryButton(title: "Cancel") { dismiss() }
            Button {
                Task {
                    if await form.run() {
                        await model.containers.load()
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    if form.busy { ProgressView().controlSize(.small) }
                    Text(form.busy ? "Running…" : "Run").font(.berthSans(12.5, .semibold))
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).disabled(!form.canRun).opacity(form.canRun ? 1 : 0.5)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: helpers

    private func labeled<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
            content()
        }
    }

    private func section<V: View>(_ title: String, add: @escaping () -> Void, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionCaption(text: title)
                Spacer()
                Button(action: add) {
                    Text("+ Add").font(.berthSans(11.5, .medium)).foregroundStyle(Theme.accent)
                }.buttonStyle(.plain)
            }
            content()
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                .frame(width: 24, height: 24)
        }.buttonStyle(.plain)
    }

    private func optionToggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(label).font(.berthSans(11.5))
        }
        .toggleStyle(.button)
        .tint(Theme.accent)
    }
}
