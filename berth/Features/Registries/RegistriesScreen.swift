//
//  RegistriesScreen.swift
//  berth
//

import SwiftUI
import ContainerResource

struct RegistriesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        let store = model.registries
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Registries",
                         subtitle: "\(store.all.count) active logins · credentials stored in keychain") {
                AccentButton(title: "Add login", systemImage: "plus") { showAdd = true }
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)

            Divider().overlay(Theme.border)

            switch store.state {
            case .idle, .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let m):
                CenteredMessage(systemImage: "exclamationmark.triangle", title: "Couldn’t read keychain", message: m)
            case .loaded:
                if store.all.isEmpty {
                    CenteredMessage(systemImage: "globe", title: "Not authenticated",
                                    message: "Add a registry login to pull and push private images.",
                                    actionTitle: "Add login") { showAdd = true }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.all) { reg in
                                row(reg, store)
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
        .sheet(isPresented: $showAdd) { addSheet(store) }
    }

    private func row(_ reg: ContainerResource.RegistryResource, _ store: RegistriesStore) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "globe").foregroundStyle(Theme.textTertiary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(reg.name).font(.berthSans(13.5, .medium)).foregroundStyle(Theme.textPrimary)
                Text("Logged in as \(reg.username)").font(.berthMono(11)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            SecondaryButton(title: "Log out") { Task { await store.logout(reg.name) } }
        }
        .padding(.horizontal, 22).frame(height: 56)
    }

    private func addSheet(_ store: RegistriesStore) -> some View {
        SheetScaffold(title: "Add registry login",
                      confirmTitle: store.busy ? "Saving…" : "Log in",
                      confirmDisabled: host.isEmpty || username.isEmpty || store.busy) {
            VStack(alignment: .leading, spacing: 12) {
                field("Registry host") { FieldText(placeholder: "ghcr.io", text: $host, mono: true) }
                field("Username") { FieldText(placeholder: "user", text: $username) }
                field("Password / token") {
                    SecureField("••••••••", text: $password)
                        .textFieldStyle(.plain).font(.berthMono(12.5)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10).frame(height: 32)
                        .background(Theme.fill).clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 1))
                }
                Text("Stored in the macOS keychain (com.apple.container.registry).")
                    .font(.berthSans(11)).foregroundStyle(Theme.textFaint)
            }
        } confirm: {
            let h = host, u = username, p = password
            Task {
                if await store.login(host: h, username: u, password: p) {
                    host = ""; username = ""; password = ""; showAdd = false
                }
            }
        }
    }

    private func field<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.berthSans(11.5)).foregroundStyle(Theme.textTertiary)
            content()
        }
    }
}
