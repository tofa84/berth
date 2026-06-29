//
//  AppModel.swift
//  berth
//
//  Composition root. Owns the service actor, the engine connection, global
//  navigation/search state, and (lazily) per-screen stores. Injected via
//  .environment so every view can reach it.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let service = ContainerService()
    let engine: EngineConnection

    var selection: SidebarItem = .dashboard
    var search: String = ""
    var showRunSheet = false
    /// When set, the next Run sheet opens pre-filled with this image reference
    /// (e.g. launched from the Images screen). Consumed once by RunContainerSheet.
    var runPrefillImage: String?

    /// Optional sidebar badge counts, filled in by feature phases.
    var counts: [SidebarItem: Int] = [:]

    // Lazily-created per-screen stores.
    @ObservationIgnored private var _containers: ContainersStore?
    var containers: ContainersStore {
        if let s = _containers { return s }
        let s = ContainersStore(service: service, app: self)
        _containers = s
        return s
    }

    @ObservationIgnored private var _dashboard: DashboardStore?
    var dashboard: DashboardStore {
        if let s = _dashboard { return s }
        let s = DashboardStore(service: service, app: self)
        _dashboard = s
        return s
    }

    @ObservationIgnored private var _images: ImagesStore?
    var images: ImagesStore {
        if let s = _images { return s }
        let s = ImagesStore(service: service, app: self)
        _images = s
        return s
    }

    @ObservationIgnored private var _volumes: VolumesStore?
    var volumes: VolumesStore {
        if let s = _volumes { return s }
        let s = VolumesStore(service: service, app: self)
        _volumes = s
        return s
    }

    @ObservationIgnored private var _networks: NetworksStore?
    var networks: NetworksStore {
        if let s = _networks { return s }
        let s = NetworksStore(service: service, app: self)
        _networks = s
        return s
    }

    @ObservationIgnored private var _system: SystemStore?
    var system: SystemStore {
        if let s = _system { return s }
        let s = SystemStore(service: service, app: self)
        _system = s
        return s
    }

    @ObservationIgnored private var _registries: RegistriesStore?
    var registries: RegistriesStore {
        if let s = _registries { return s }
        let s = RegistriesStore(service: service, app: self)
        _registries = s
        return s
    }

    init() {
        engine = EngineConnection(service: service)
    }

    /// Open the Run sheet, optionally pre-filled with an image reference.
    func openRunSheet(image: String? = nil) {
        runPrefillImage = image
        showRunSheet = true
    }

    func bootstrap() {
        engine.startMonitoring()
    }
}
