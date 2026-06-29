//
//  SidebarItem.swift
//  berth
//

import Foundation

enum SidebarSection: String, CaseIterable {
    case workspace = "WORKSPACE"
    case system = "SYSTEM"
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, containers, images, volumes, networks, builds
    case registries, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .containers: "Containers"
        case .images: "Images"
        case .volumes: "Volumes"
        case .networks: "Networks"
        case .builds: "Builds"
        case .registries: "Registries"
        case .system: "System"
        }
    }

    /// Placeholder for the global search field on this screen, or `nil` when the
    /// screen has no searchable list (the top-bar field is hidden there).
    var searchPlaceholder: String? {
        switch self {
        case .containers: "Search containers…"
        case .images: "Search images…"
        case .volumes: "Search volumes…"
        case .networks: "Search networks…"
        case .registries: "Search registries…"
        case .dashboard, .builds, .system: nil
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .containers: "rectangle.stack"
        case .images: "square.on.square"
        case .volumes: "cylinder"
        case .networks: "network"
        case .builds: "hammer"
        case .registries: "globe"
        case .system: "slider.horizontal.3"
        }
    }

    var section: SidebarSection {
        switch self {
        case .registries, .system: .system
        default: .workspace
        }
    }

    static func items(in section: SidebarSection) -> [SidebarItem] {
        allCases.filter { $0.section == section }
    }
}
