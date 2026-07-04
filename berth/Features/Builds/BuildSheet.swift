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
            SheetHeader(systemImage: "hammer.fill", title: "Build an image", command: "container build")
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextSection(form)
                    tagSection(form)
                    argsSection(form)
                    labelsSection(form)
                    platformSection(form)
                    optionsSection(form)
                    CommandPreviewPanel(command: form.commandPreview)
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

    private func contextSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            FormField("Build context") {
                HStack(spacing: 8) {
                    FieldText(placeholder: "/path/to/project", text: $form.contextDir, mono: true)
                    SecondaryButton(title: "Choose…", systemImage: "folder") { chooseContext(form) }
                }
            }
            FormField("Dockerfile") {
                FieldText(placeholder: "defaults to <context>/Dockerfile", text: $form.dockerfileOverride, mono: true)
            }
        }
    }

    private func tagSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return FormField("Tag") {
            FieldText(placeholder: "myimage:latest", text: $form.tag, mono: true)
        }
    }

    private func argsSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return FormSection("Build args", onAdd: { form.addArg() }) {
            ForEach($form.buildArgs) { $arg in
                KeyValueFieldRow(pair: $arg) { form.buildArgs.removeAll { $0.id == arg.id } }
            }
        }
    }

    private func labelsSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return FormSection("Labels", onAdd: { form.addLabel() }) {
            ForEach($form.labels) { $label in
                KeyValueFieldRow(pair: $label) { form.labels.removeAll { $0.id == label.id } }
            }
        }
    }

    private func platformSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            SectionCaption(text: "Platforms")
            FlowLayout(spacing: 10) {
                OptionToggle("linux/arm64", $form.platformARM64)
                OptionToggle("linux/amd64", $form.platformAMD64)
            }
            FormField("Target stage") {
                FieldText(placeholder: "optional (multi-stage)", text: $form.target)
            }
        }
    }

    private func optionsSection(_ form: BuildFormModel) -> some View {
        @Bindable var form = form
        return VStack(alignment: .leading, spacing: 10) {
            SectionCaption(text: "Options")
            FlowLayout(spacing: 10) {
                OptionToggle("No cache --no-cache", $form.noCache)
                OptionToggle("Always pull base --pull", $form.pull)
            }
        }
    }

    private func footer(_ form: BuildFormModel) -> some View {
        HStack {
            if let error = form.validationError {
                Text(error).font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary).lineLimit(2)
            }
            Spacer()
            SecondaryButton(title: "Cancel") { dismiss() }
            AccentButton(title: "Build") {
                model.builds.startBuild(form.request())
                model.selection = .builds
                dismiss()
            }
            .disabled(!form.canBuild)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

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
}
