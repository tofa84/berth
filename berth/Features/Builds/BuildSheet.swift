//
//  BuildSheet.swift
//  berth
//
//  The build form. Mirrors RunContainerSheet: sections + a live command preview
//  that reflects the equivalent `container build …` command. Execution is
//  native gRPC — submitting hands the request to BuildsStore and switches to the
//  Builds screen to watch progress.
//

import SwiftUI
import AppKit

struct BuildSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var form = BuildFormModel()

    var body: some View {
        @Bindable var form = form
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextSection(form)
                    tagSection(form)
                    argsSection(form)
                    labelsSection(form)
                    platformSection(form)
                    optionsSection(form)
                    previewSection(form)
                }
                .padding(20)
            }
            Divider().overlay(Theme.border)
            footer(form)
        }
        .frame(width: 580, height: 640)
        .background(Theme.bg)
        .onAppear {
            if let prefill = model.buildPrefill {
                form.fill(from: prefill)
                model.buildPrefill = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill").foregroundStyle(Theme.accent)
            Text("Build an image").font(.berthSans(16, .semibold)).foregroundStyle(Theme.textPrimary)
            Text("container build").font(.berthMono(11)).foregroundStyle(Theme.textFaint)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(Theme.textTertiary).frame(width: 26, height: 26)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func contextSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            labeled("Build context") {
                HStack(spacing: 8) {
                    FieldText(placeholder: "/path/to/project", text: $form.contextDir, mono: true)
                    SecondaryButton(title: "Choose…", systemImage: "folder") { chooseContext(form) }
                }
            }
            labeled("Dockerfile") {
                FieldText(placeholder: "defaults to <context>/Dockerfile", text: $form.dockerfileOverride, mono: true)
            }
        }
    }

    private func tagSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return labeled("Tag") {
            FieldText(placeholder: "myimage:latest", text: $form.tag, mono: true)
        }
    }

    private func argsSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return section("Build args", add: { form.addArg() }) {
            ForEach($form.buildArgs) { $arg in
                HStack(spacing: 8) {
                    FieldText(placeholder: "KEY", text: $arg.key, mono: true)
                    Text("=").foregroundStyle(Theme.textFaint)
                    FieldText(placeholder: "value", text: $arg.value, mono: true)
                    removeButton { form.buildArgs.removeAll { $0.id == arg.id } }
                }
            }
        }
    }

    private func labelsSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return section("Labels", add: { form.addLabel() }) {
            ForEach($form.labels) { $label in
                HStack(spacing: 8) {
                    FieldText(placeholder: "KEY", text: $label.key, mono: true)
                    Text("=").foregroundStyle(Theme.textFaint)
                    FieldText(placeholder: "value", text: $label.value, mono: true)
                    removeButton { form.labels.removeAll { $0.id == label.id } }
                }
            }
        }
    }

    private func platformSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            SectionCaption(text: "Platforms")
            FlowLayout(spacing: 10) {
                optionToggle("linux/arm64", $form.platformARM64)
                optionToggle("linux/amd64", $form.platformAMD64)
            }
            labeled("Target stage") {
                FieldText(placeholder: "optional (multi-stage)", text: $form.target)
            }
        }
    }

    private func optionsSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            SectionCaption(text: "Options")
            FlowLayout(spacing: 10) {
                optionToggle("No cache --no-cache", $form.noCache)
                optionToggle("Always pull base --pull", $form.pull)
            }
        }
    }

    private func previewSection(_ form: BuildFormModel) -> some View {
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

    private func footer(_ form: BuildFormModel) -> some View {
        HStack {
            if let error = form.validationError {
                Text(error).font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary).lineLimit(2)
            }
            Spacer()
            SecondaryButton(title: "Cancel") { dismiss() }
            Button {
                model.builds.startBuild(form.request())
                model.selection = .builds
                dismiss()
            } label: {
                Text("Build")
                    .font(.berthSans(12.5, .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).disabled(!form.canBuild).opacity(form.canBuild ? 1 : 0.5)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: helpers

    private func chooseContext(_ form: BuildFormModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the build context folder"
        if panel.runModal() == .OK, let url = panel.url {
            form.contextDir = url.path
        }
    }

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
