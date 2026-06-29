//
//  NetworksScreen.swift
//  berth
//

import SwiftUI
import ContainerResource

struct NetworksScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showCreate = false
    @State private var newName = ""
    @State private var pendingDelete: String?

    private let cols = (driver: 90.0, subnet: 160.0, gateway: 150.0, containers: 90.0, actions: 44.0)

    var body: some View {
        let store = model.networks
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Networks", subtitle: subtitle(store)) {
                AccentButton(title: "Create", systemImage: "plus") { showCreate = true }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)

            header
            Divider().overlay(Theme.border)

            switch store.state {
            case .idle, .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let m):
                CenteredMessage(systemImage: "exclamationmark.triangle", title: "Couldn’t load networks", message: m)
            case .loaded:
                if store.all.isEmpty {
                    CenteredMessage(systemImage: "network", title: "No networks", message: "Create a network to connect containers.", actionTitle: "Create network") { showCreate = true }
                } else {
                    let shown = store.displayed(matching: model.search)
                    if shown.isEmpty {
                        CenteredMessage(systemImage: "magnifyingglass", title: "No matching networks",
                                        message: "No network matches the current search.")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(shown) { n in
                                    row(n, store)
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
        .task(id: model.engine.epoch) { await store.load() }
        .sheet(isPresented: $showCreate) { createSheet(store) }
        .confirmationDialog("Delete network?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete { Task { await store.delete(id) } }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removes the network. Containers must be detached first.")
        }
    }

    private func subtitle(_ s: NetworksStore) -> String {
        let attachments = s.all.reduce(0) { $0 + s.usedBy($1) }
        return "\(s.all.count) networks · vmnet · \(attachments) attachments"
    }

    private var header: some View {
        HStack(spacing: 0) {
            cell("NAME", nil)
            cell("DRIVER", cols.driver)
            cell("SUBNET", cols.subnet)
            cell("GATEWAY", cols.gateway)
            cell("CONTAINERS", cols.containers)
            Spacer().frame(width: cols.actions)
        }
        .font(.berthSans(10, .semibold)).tracking(0.7).foregroundStyle(Theme.textFaint)
        .padding(.horizontal, 22).padding(.bottom, 8)
    }

    private func cell(_ t: String, _ w: Double?) -> some View {
        Text(t).frame(width: w.map { CGFloat($0) }, alignment: .leading)
            .frame(maxWidth: w == nil ? .infinity : nil, alignment: .leading)
    }

    private func row(_ n: NetworkResource, _ store: NetworksStore) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(n.name).font(.berthSans(13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if n.isBuiltin { Tag("DEFAULT") }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 10)
            mono(n.driverLabel, cols.driver)
            mono(n.subnetText, cols.subnet)
            mono(n.gatewayText, cols.gateway)
            mono(store.usedBy(n) == 0 ? "—" : "\(store.usedBy(n))", cols.containers)
            Group {
                if n.isBuiltin {
                    Spacer().frame(width: cols.actions)
                } else {
                    Menu {
                        Button("Delete", role: .destructive) { pendingDelete = n.id }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
                            .frame(width: cols.actions, height: 28)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
        }
        .padding(.horizontal, 22).frame(height: 52)
    }

    private func mono(_ t: String, _ w: Double) -> some View {
        Text(t).font(.berthMono(11.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            .frame(width: w, alignment: .leading)
    }

    private func createSheet(_ store: NetworksStore) -> some View {
        SheetScaffold(title: "Create network", confirmTitle: store.busy ? "Creating…" : "Create",
                      confirmDisabled: newName.isEmpty || store.busy) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
                FieldText(placeholder: "my-network", text: $newName)
                Text("Creates a NAT network via the vmnet plugin.")
                    .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
            }
        } confirm: {
            let n = newName
            Task { await store.create(name: n); if store.actionError == nil { newName = ""; showCreate = false } }
        }
    }
}
