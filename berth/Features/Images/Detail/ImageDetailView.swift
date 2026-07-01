//
//  ImageDetailView.swift
//  berth
//
//  Per-image detail, mirroring the container detail's Overview/Inspect pattern.
//  Everything here is sourced from the image's `variantInfos` — a flattened view
//  of each platform variant's OCI config + history, already decoded by
//  `listImages()` — so no extra engine round-trips are needed. (The OCI member
//  access lives in UIModels; this file stays OCI-free so `Image`/`State` resolve
//  unambiguously to SwiftUI.)
//

import SwiftUI
import ContainerResource

struct ImageDetailView: View {
    @Environment(AppModel.self) private var model
    let reference: String
    @State private var tab: Tab = .overview
    @State private var platformIndex = 0
    @State private var confirmDelete = false

    init(reference: String) { self.reference = reference }

    enum Tab: String, CaseIterable {
        case overview = "Overview", layers = "Layers", inspect = "Inspect"
    }

    var body: some View {
        let store = model.images
        Group {
            if let img = store.image(reference) {
                VStack(spacing: 0) {
                    headerBar(img, store)
                    tabBar
                    ScrollView { content(img).padding(22) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .confirmationDialog("Delete image?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { Task { await store.delete(img.name) } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes the image from local storage. This can’t be undone.")
                }
            } else {
                CenteredMessage(systemImage: "questionmark.square.dashed",
                                title: "Image not found",
                                message: "It may have been deleted.",
                                actionTitle: "Back to list") { store.selectedID = nil }
            }
        }
        .task(id: reference) { platformIndex = 0 }   // reset arch when switching images
    }

    // The variant whose config/history is currently shown (multi-arch aware).
    private func info(_ infos: [ImageVariantInfo]) -> ImageVariantInfo? {
        infos.indices.contains(platformIndex) ? infos[platformIndex] : infos.first
    }

    // MARK: Header

    private func headerBar(_ img: ContainerResource.ImageResource, _ store: ImagesStore) -> some View {
        HStack(spacing: 14) {
            Button { store.selectedID = nil } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary).frame(width: 30, height: 30)
                    .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Image(systemName: "square.on.square").font(.system(size: 15)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(img.repository).font(.berthSans(17, .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("\(img.tag) · \(img.shortDigest)").font(.berthMono(11.5)).foregroundStyle(Theme.textTertiary)
            }
            Text(Format.bytes(img.totalSize)).font(.berthMono(11)).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            if store.busy { ProgressView().controlSize(.small) }
            AccentButton(title: "Run", systemImage: "play.fill") { model.openRunSheet(image: img.name) }
            copyMenu(img)
            SecondaryButton(title: "Delete", systemImage: "trash", role: .destructive) {
                confirmDelete = true
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func copyMenu(_ img: ContainerResource.ImageResource) -> some View {
        Menu {
            Button("Copy reference") { Pasteboard.copy(img.name) }
            Button("Copy digest") { Pasteboard.copy(img.fullDigest) }
            Button("Copy image ID") { Pasteboard.copy(img.shortDigest) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                Text("Copy")
            }
            .font(.berthSans(12)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(Tab.allCases, id: \.self) { t in
                let active = t == tab
                Text(t.rawValue)
                    .font(.berthSans(12.5, active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { if active { Rectangle().fill(Theme.accent).frame(height: 2) } }
                    .contentShape(Rectangle())
                    .onTapGesture { tab = t }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private func content(_ img: ContainerResource.ImageResource) -> some View {
        switch tab {
        case .overview: overview(img)
        case .layers: layers(img)
        case .inspect: inspect(img)
        }
    }

    // MARK: Platform picker (multi-arch)

    @ViewBuilder
    private func platformPicker(_ infos: [ImageVariantInfo]) -> some View {
        if infos.count > 1 {
            HStack(spacing: 10) {
                SectionCaption(text: "Platform")
                Picker("", selection: $platformIndex) {
                    ForEach(infos) { v in Text(v.platform).tag(v.id) }
                }
                .labelsHidden().pickerStyle(.menu).tint(Theme.textSecondary).fixedSize()
                Text("amd64 images run under emulation on Apple silicon.")
                    .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
                Spacer()
            }
        }
    }

    // MARK: Overview

    private func overview(_ img: ContainerResource.ImageResource) -> some View {
        let infos = img.variantInfos
        let v = info(infos)
        return VStack(alignment: .leading, spacing: 14) {
            platformPicker(infos)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], spacing: 14) {
                InfoCard(title: "Image") {
                    KeyValue("Reference", img.name)
                    KeyValue("Digest", img.shortDigest)
                    KeyValue("Created", Format.relative(img.creationDate))
                    KeyValue("Size", Format.bytes(img.totalSize))
                    KeyValue("Used by", usedByText(img))
                    KeyValue("Architectures", img.platformsText)
                }
                InfoCard(title: "Configuration") {
                    KeyValue("OS / Arch", v?.osArch ?? "—")
                    KeyValue("Entrypoint", v?.entrypoint ?? "—")
                    KeyValue("Command", v?.command ?? "—")
                    KeyValue("User", v?.user ?? "—")
                    KeyValue("Working dir", v?.workingDir ?? "—")
                    KeyValue("Stop signal", v?.stopSignal ?? "—")
                }
                InfoCard(title: "Environment") {
                    let env = v?.env ?? []
                    if env.isEmpty {
                        Text("No variables").font(.berthSans(12)).foregroundStyle(Theme.textTertiary)
                    } else {
                        EnvList(items: env)
                    }
                }
                InfoCard(title: "Labels") {
                    let labels = v?.labels ?? []
                    if labels.isEmpty {
                        Text("No labels").font(.berthSans(12)).foregroundStyle(Theme.textTertiary)
                    } else {
                        ForEach(labels, id: \.key) { label in KeyValue(label.key, label.value) }
                    }
                }
            }
        }
    }

    // MARK: Layers (image history — the `docker history` equivalent)

    private func layers(_ img: ContainerResource.ImageResource) -> some View {
        let infos = img.variantInfos
        let history = info(infos)?.layers ?? []
        return VStack(alignment: .leading, spacing: 14) {
            platformPicker(infos)
            if history.isEmpty {
                Text("No layer history recorded for this image.")
                    .font(.berthSans(12.5)).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(history) { layer in
                            layerRow(layer)
                            if layer.id < history.count - 1 { Divider().overlay(Theme.border) }
                        }
                    }
                }
                Text("\(history.count) build steps · layers marked “empty” added no filesystem changes.")
                    .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
            }
        }
    }

    private func layerRow(_ layer: ImageLayerInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(layer.id)").font(.berthMono(11)).foregroundStyle(Theme.textFaint)
                .frame(width: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                commandText(layer.commandParts).font(.berthMono(11.5))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(historyDate(layer.created)).font(.berthSans(10.5)).foregroundStyle(Theme.textFaint)
                    if layer.empty {
                        Text("empty").font(.berthSans(10)).foregroundStyle(Theme.textFaint)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    /// The instruction word (RUN, ENV, …) and the trailing "# buildkit" marker
    /// recede so the actual command leads.
    private func commandText(_ parts: ImageLayerInfo.CommandParts) -> Text {
        var text = Text("")
        if let instruction = parts.instruction {
            text = Text("\(instruction) ").foregroundStyle(Theme.textFaint)
        }
        text = text + Text(parts.body).foregroundStyle(Theme.textSecondary)
        if let comment = parts.comment {
            text = text + Text(" \(comment)").foregroundStyle(Theme.textFaint)
        }
        return text
    }

    // MARK: Inspect

    private func inspect(_ img: ContainerResource.ImageResource) -> some View {
        ScrollView(.horizontal) {
            Text(json(img))
                .font(.berthMono(11.5)).foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled).padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 460)
        .background(Theme.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Helpers

    private func usedByText(_ img: ContainerResource.ImageResource) -> String {
        let n = model.images.usedBy(img)
        return n == 0 ? "Not in use" : "\(n) container\(n == 1 ? "" : "s")"
    }

    private func historyDate(_ s: String) -> String {
        guard !s.isEmpty else { return "—" }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s) {
            return Format.relative(d)
        }
        return s
    }

    private func json(_ img: ContainerResource.ImageResource) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(img), let s = String(data: data, encoding: .utf8) else {
            return "Failed to encode image."
        }
        return s
    }
}
