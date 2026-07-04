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
            SheetHeader(systemImage: "play.fill", title: "Run a container", command: "container run")
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identitySection(form)
                    envSection(form)
                    portsSection(form)
                    resourcesSection(form)
                    optionsSection(form)
                    CommandPreviewPanel(command: form.commandPreview)
                }
                .padding(20)
            }
            Divider().overlay(Theme.border)
            footer(form)
        }
        .frame(width: 580, height: 620)
        .background(Theme.bg)
        .onAppear {
            // Launched from the Images screen with a chosen image — pre-fill once.
            if let img = model.runPrefillImage {
                form.image = img
                model.runPrefillImage = nil
            }
        }
    }

    private func identitySection(_ form: RunFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                FormField("Image") { FieldText(placeholder: "nginx:latest", text: $form.image, mono: true) }
                FormField("Name") { FieldText(placeholder: "optional", text: $form.name) }.frame(width: 180)
            }
            FormField("Platform") {
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
        return FormSection("Environment", onAdd: { form.addEnv() }) {
            ForEach($form.env) { $e in
                KeyValueFieldRow(pair: $e) { form.env.removeAll { $0.id == e.id } }
            }
        }
    }

    private func portsSection(_ form: RunFormModel) -> some View {
        @Bindable var form = form
        return FormSection("Published ports", onAdd: { form.addPort() }) {
            ForEach($form.ports) { $p in
                HStack(spacing: 8) {
                    FieldText(placeholder: "8080", text: $p.host, mono: true)
                    Text(":").foregroundStyle(Theme.textFaint)
                    FieldText(placeholder: "80", text: $p.container, mono: true)
                    Toggle("UDP", isOn: $p.udp).toggleStyle(.button).font(.berthSans(11))
                    RemoveRowButton { form.ports.removeAll { $0.id == p.id } }
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
                OptionToggle("Remove on exit --rm", $form.remove)
                OptionToggle("Read-only", $form.readOnly)
                OptionToggle("Rosetta", $form.rosetta)
            }
            Text("Runs detached — follow output in the container's Logs tab.")
                .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
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
                        // Surface the freshly-started container regardless of where
                        // Run was launched from (Images screen, top bar, …).
                        model.selection = .containers
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
}
