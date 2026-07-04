//
//  RootView.swift
//  berth
//
//  Window shell: full-width TopBar over [sidebar | detail]. Replaces the
//  Phase-0 ContentView spike.
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TopBar()
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                SidebarView().frame(width: 220)
                Rectangle().fill(Theme.border).frame(width: 1)
                DetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
        .frame(minWidth: 1040, minHeight: 660)
        // A query only makes sense within one resource list; reset it on switch so
        // a leftover term doesn't silently empty the next screen.
        .onChange(of: model.selection) { model.search = "" }
        .sheet(isPresented: $model.showRunSheet) {
            RunContainerSheet()
        }
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.bg
            switch model.engine.state {
            case .down(let message):
                CenteredMessage(
                    systemImage: "bolt.horizontal.circle",
                    title: "API server not running",
                    message: message,
                    actionTitle: model.engine.starting ? "Starting…" : "Start engine",
                    action: { Task { await model.engine.startEngine() } }
                )
            case .connecting, .running:
                VStack(spacing: 0) {
                    if model.engine.versionMismatch {
                        VersionBanner(engineVersion: model.engine.version ?? "?")
                    }
                    screen
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    @ViewBuilder private var screen: some View {
        // Real screens are routed here as each phase lands; placeholder until then.
        switch model.selection {
        case .dashboard: DashboardScreen()
        case .containers: ContainersScreen()
        case .images: ImagesScreen()
        case .volumes: VolumesScreen()
        case .networks: NetworksScreen()
        case .system: SystemScreen()
        case .registries: RegistriesScreen()
        case .builds: BuildsScreen()
        }
    }
}

struct VersionBanner: View {
    let engineVersion: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Engine is \(engineVersion); app was built against \(EngineConnection.pinnedVersion). Some features may misbehave.")
            Spacer()
        }
        .font(.berthSans(11.5))
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.amber.opacity(0.10))
    }
}

struct ComingSoon: View {
    let item: SidebarItem
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: item.title, subtitle: "Coming soon")
            Spacer()
            CenteredMessage(
                systemImage: item.icon,
                title: item.title,
                message: "This screen is part of a later build phase."
            )
        }
        .padding(22)
    }
}

