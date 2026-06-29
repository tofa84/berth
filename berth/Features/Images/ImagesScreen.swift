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

    private let cols = (tag: 110.0, id: 110.0, arch: 120.0, size: 90.0, created: 110.0, used: 70.0, actions: 44.0)

    var body: some View {
        let store = model.images
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Images", subtitle: subtitle(store)) {
                HStack(spacing: 10) {
                    SecondaryButton(title: "Prune unused") { Task { await store.prune() } }
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
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.all) { img in
                                row(img, store)
                                Divider().overlay(Theme.border)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { if let e = store.actionError { ErrorToast(text: e) } }
        .task { await store.load() }
        .sheet(isPresented: $showPull) { pullSheet(store) }
    }

    private func subtitle(_ s: ImagesStore) -> String {
        let total = s.all.reduce(Int64(0)) { $0 + $1.totalSize }
        return "\(s.all.count) images · \(Format.bytes(total)) on disk"
    }

    private var header: some View {
        HStack(spacing: 0) {
            cell("REPOSITORY", nil)
            cell("TAG", cols.tag)
            cell("IMAGE ID", cols.id)
            cell("OS / ARCH", cols.arch)
            cell("SIZE", cols.size)
            cell("CREATED", cols.created)
            cell("USED BY", cols.used)
            Spacer().frame(width: cols.actions)
        }
        .font(.berthSans(10, .semibold)).tracking(0.7).foregroundStyle(Theme.textFaint)
        .padding(.horizontal, 22).padding(.bottom, 8)
    }

    private func cell(_ t: String, _ w: Double?) -> some View {
        Text(t).frame(width: w.map { CGFloat($0) }, alignment: .leading)
            .frame(maxWidth: w == nil ? .infinity : nil, alignment: .leading)
    }

    private func row(_ img: ContainerResource.ImageResource, _ store: ImagesStore) -> some View {
        HStack(spacing: 0) {
            Text(img.repository).font(.berthSans(13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 10)
            mono(img.tag, cols.tag)
            mono(img.shortDigest, cols.id)
            mono(img.platformsText, cols.arch)
            mono(Format.bytes(img.totalSize), cols.size)
            mono(Format.relative(img.creationDate), cols.created)
            mono(store.usedBy(img) == 0 ? "—" : "\(store.usedBy(img))", cols.used)
            Menu {
                Button("Delete", role: .destructive) { Task { await store.delete(img.name) } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
                    .frame(width: cols.actions, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 22).frame(height: 52)
    }

    private func mono(_ t: String, _ w: Double) -> some View {
        Text(t).font(.berthMono(11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            .frame(width: w, alignment: .leading)
    }

    private func pullSheet(_ store: ImagesStore) -> some View {
        SheetScaffold(title: "Pull image", confirmTitle: store.busy ? "Pulling…" : "Pull",
                      confirmDisabled: pullRef.isEmpty || store.busy) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reference").font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
                FieldText(placeholder: "docker.io/library/nginx:latest", text: $pullRef)
                Text("Pulls from the configured registry and unpacks for the current platform.")
                    .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
            }
        } confirm: {
            let ref = pullRef
            Task { await store.pull(reference: ref); if store.actionError == nil { pullRef = ""; showPull = false } }
        }
    }
}
