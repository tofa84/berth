//
//  ImagesScreen.swift
//  berth
//

import SwiftUI
import ContainerResource

struct ImagesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showPull = false
    @State private var pullRef = ""
    @State private var confirmPrune = false
    @State private var pendingDelete: String?

    private let cols = (tag: 116.0, id: 100.0, arch: 100.0, size: 84.0, created: 96.0, used: 64.0, actions: 64.0, chevron: 20.0)

    var body: some View {
        let store = model.images
        Group {
            if let id = store.selectedID {
                ImageDetailView(reference: id)
            } else {
                list(store)
            }
        }
        .task(id: model.engine.epoch) { await store.load() }
        .sheet(isPresented: $showPull) { pullSheet(store) }
    }

    // MARK: List

    @ViewBuilder
    private func list(_ store: ImagesStore) -> some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Images", subtitle: subtitle(store)) {
                HStack(spacing: 10) {
                    sortMenu($store)
                    Toggle(isOn: $store.unusedOnly) {
                        Text("Unused only").font(.berthSans(12))
                    }
                    .toggleStyle(.button).tint(Theme.accent)
                    SecondaryButton(title: "Prune unused") { confirmPrune = true }
                        .disabled(store.unusedCount == 0)
                    AccentButton(title: "Pull", systemImage: "arrow.down.circle") { showPull = true }
                }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)

            header
            Divider().overlay(Theme.border)

            switch store.state {
            case .idle, .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let m):
                CenteredMessage(systemImage: "exclamationmark.triangle", title: "Couldn’t load images", message: m)
            case .loaded:
                if store.all.isEmpty {
                    CenteredMessage(systemImage: "square.on.square", title: "No images", message: "Pull an image to get started.", actionTitle: "Pull image") { showPull = true }
                } else {
                    let shown = store.displayed(matching: model.search)
                    if shown.isEmpty {
                        CenteredMessage(systemImage: "magnifyingglass", title: "No matching images",
                                        message: "No image matches the current search or filter.")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(shown) { img in
                                    row(img, store)
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { if let e = store.actionError { ErrorToast(text: e) } }
        .confirmationDialog("Prune unused images?",
                            isPresented: $confirmPrune, titleVisibility: .visible) {
            Button("Delete \(store.unusedCount) unused", role: .destructive) {
                Task { await store.prune() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes every image not used by a container, and reclaims orphaned data.")
        }
        .confirmationDialog("Delete image?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let ref = pendingDelete { Task { await store.delete(ref) } }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removes the image from local storage. This can’t be undone.")
        }
    }

    private func sortMenu(_ store: Bindable<ImagesStore>) -> some View {
        Menu {
            Picker("Sort", selection: store.sort) {
                ForEach(ImagesStore.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text(store.wrappedValue.sort.rawValue)
            }
            .font(.berthSans(12)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func subtitle(_ s: ImagesStore) -> String {
        let total = s.all.reduce(Int64(0)) { $0 + $1.totalSize }
        return "\(s.all.count) images · \(Format.bytes(total)) on disk · click a row to inspect"
    }

    private var header: some View {
        HStack(spacing: 0) {
            cell("REPOSITORY", nil)
            cell("TAG", cols.tag)
            cell("IMAGE ID", cols.id)
            cell("OS / ARCH", cols.arch)
            cell("SIZE", cols.size, alignment: .trailing)
            cell("CREATED", cols.created)
            cell("USED BY", cols.used)
            Spacer().frame(width: cols.actions + cols.chevron)
        }
        .font(.berthSans(10, .semibold)).tracking(0.7).foregroundStyle(Theme.textFaint)
        .padding(.horizontal, 22).padding(.bottom, 8)
    }

    private func cell(_ t: String, _ w: Double?, alignment: Alignment = .leading) -> some View {
        Text(t)
            // Right-aligned columns keep a gutter inside their fixed frame so
            // the digits don't touch the next column (the HStack has spacing 0).
            .padding(.trailing, alignment == .trailing ? 12 : 0)
            .frame(width: w.map { CGFloat($0) }, alignment: alignment)
            .frame(maxWidth: w == nil ? .infinity : nil, alignment: alignment)
    }

    private func row(_ img: ContainerResource.ImageResource, _ store: ImagesStore) -> some View {
        HStack(spacing: 0) {
            // Middle truncation keeps registry and image name readable
            // ("ghcr.io/apple/…/vminit"); the tooltip carries the full value.
            Text(img.repository).font(.berthSans(13)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).truncationMode(.middle).help(img.repository)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 10)
            mono(img.tag, cols.tag, help: img.tag)
            mono(img.shortDigest, cols.id)
            mono(img.archSummaryText, cols.arch, help: img.platformsText)
            mono(Format.bytes(img.totalSize), cols.size, alignment: .trailing)
            mono(Format.relative(img.creationDate), cols.created)
            mono(store.usedBy(img) == 0 ? "—" : "\(store.usedBy(img))", cols.used)

            HStack(spacing: 6) {
                Button { model.openRunSheet(image: img.name) } label: {
                    Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(Theme.greenBright)
                        .frame(width: 28, height: 28)
                        .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain).help("Run a container from this image")

                Menu {
                    Button("Run…") { model.openRunSheet(image: img.name) }
                    Divider()
                    Button("Copy reference") { Pasteboard.copy(img.name) }
                    Button("Copy digest") { Pasteboard.copy(img.fullDigest) }
                    Button("Copy image ID") { Pasteboard.copy(img.shortDigest) }
                    Divider()
                    Button("Delete", role: .destructive) { pendingDelete = img.name }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .frame(width: cols.actions, alignment: .leading)

            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                .frame(width: cols.chevron)
        }
        .padding(.horizontal, 22).frame(height: 52)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = img.name }
    }

    @ViewBuilder
    private func mono(_ t: String, _ w: Double, alignment: Alignment = .leading, help: String? = nil) -> some View {
        let text = Text(t).font(.berthMono(11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            .padding(.trailing, alignment == .trailing ? 12 : 0)
            .frame(width: w, alignment: alignment)
        if let help { text.help(help) } else { text }
    }

    // MARK: Pull sheet

    private func pullSheet(_ store: ImagesStore) -> some View {
        SheetScaffold(title: "Pull image", confirmTitle: store.busy ? "Pulling…" : "Pull",
                      confirmDisabled: pullRef.isEmpty || store.busy) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Reference").font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
                FieldText(placeholder: "docker.io/library/nginx:latest", text: $pullRef)
                if store.busy {
                    pullProgress(store)
                } else {
                    Text("Pulls from the configured registry and unpacks for the current platform.")
                        .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
                }
            }
        } confirm: {
            let ref = pullRef
            Task { await store.pull(reference: ref); if store.actionError == nil { pullRef = ""; showPull = false } }
        }
    }

    @ViewBuilder
    private func pullProgress(_ store: ImagesStore) -> some View {
        let p = store.pullProgress
        VStack(alignment: .leading, spacing: 6) {
            if let p, let fraction = p.fraction {
                ProgressView(value: fraction).tint(Theme.accent)
                HStack {
                    Text(p.phase).font(.berthSans(11)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    Spacer()
                    Text("\(Format.bytes(p.received)) / \(Format.bytes(p.total))")
                        .font(.berthMono(10.5)).foregroundStyle(Theme.textFaint)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(p?.phase ?? "Starting…").font(.berthSans(11)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
        }
    }
}
