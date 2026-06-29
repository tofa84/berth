//
//  VolumesScreen.swift
//  berth
//

import SwiftUI
import ContainerResource

struct VolumesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showCreate = false
    @State private var newName = ""
    @State private var newSize = ""

    private let cols = (driver: 90.0, size: 90.0, mount: 220.0, used: 70.0, created: 110.0, actions: 44.0)

    var body: some View {
        let store = model.volumes
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Volumes",
                         subtitle: "\(store.all.count) volumes · \(store.anonymousCount) anonymous") {
                HStack(spacing: 10) {
                    SecondaryButton(title: "Prune unused") { Task { await store.prune() } }
                    AccentButton(title: "Create", systemImage: "plus") { showCreate = true }
                }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)

            header
            Divider().overlay(Theme.border)

            switch store.state {
            case .idle, .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let m):
                CenteredMessage(systemImage: "exclamationmark.triangle", title: "Couldn’t load volumes", message: m)
            case .loaded:
                if store.all.isEmpty {
                    CenteredMessage(systemImage: "cylinder", title: "No volumes", message: "Create a volume to persist data.", actionTitle: "Create volume") { showCreate = true }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.all) { v in
                                row(v, store)
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
        .sheet(isPresented: $showCreate) { createSheet(store) }
    }

    private var header: some View {
        HStack(spacing: 0) {
            cell("NAME", nil)
            cell("DRIVER", cols.driver)
            cell("SIZE", cols.size)
            cell("MOUNT POINT", cols.mount)
            cell("USED BY", cols.used)
            cell("CREATED", cols.created)
            Spacer().frame(width: cols.actions)
        }
        .font(.berthSans(10, .semibold)).tracking(0.7).foregroundStyle(Theme.textFaint)
        .padding(.horizontal, 22).padding(.bottom, 8)
    }

    private func cell(_ t: String, _ w: Double?) -> some View {
        Text(t).frame(width: w.map { CGFloat($0) }, alignment: .leading)
            .frame(maxWidth: w == nil ? .infinity : nil, alignment: .leading)
    }

    private func row(_ v: VolumeConfiguration, _ store: VolumesStore) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(v.name).font(.berthSans(13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if v.isAnonymous { Tag("ANON") }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 10)
            mono(v.driver, cols.driver)
            mono(v.sizeText, cols.size)
            mono(v.mountPoint, cols.mount)
            mono(store.usedBy(v) == 0 ? "—" : "\(store.usedBy(v))", cols.used)
            mono(Format.relative(v.creationDate), cols.created)
            Menu {
                Button("Delete", role: .destructive) { Task { await store.delete(v.name) } }
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

    private func createSheet(_ store: VolumesStore) -> some View {
        SheetScaffold(title: "Create volume", confirmTitle: store.busy ? "Creating…" : "Create",
                      confirmDisabled: newName.isEmpty || store.busy) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
                    FieldText(placeholder: "my-volume", text: $newName)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Size (optional)").font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
                    FieldText(placeholder: "10G", text: $newSize)
                }
            }
        } confirm: {
            let n = newName, s = newSize
            Task { await store.create(name: n, size: s.isEmpty ? nil : s); if store.actionError == nil { newName = ""; newSize = ""; showCreate = false } }
        }
    }
}

struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.berthMono(9)).foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
