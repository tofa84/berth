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
    /// The engine gateway. `ContainerService` in the app; Layer-B tests inject
    /// a `FakeContainerService` and reach the stores via the lazy accessors.
    let service: any ContainerServicing
    let engine: EngineConnection

    var selection: SidebarItem = .dashboard
    var search: String = ""
    var showRunSheet = false
    /// When set, the next Run sheet opens pre-filled with this image reference
    /// (e.g. launched from the Images screen). Consumed once by RunContainerSheet.
    var runPrefillImage: String?

    /// Optional sidebar badge counts, filled in by feature phases.
    var counts: [SidebarItem: Int] = [:]

    /// When set, the next Build sheet opens pre-filled with this request (e.g.
    /// re-running a history entry). Consumed once by BuildSheet.
    var buildPrefill: BuildRequest?

    /// Shared single-flight source for the container list (see ContainersFeed).
    @ObservationIgnored lazy var containersFeed = ContainersFeed(service: service, app: self)

    // Lazily-created per-screen stores. Only the stores' own @Observable state
    // drives the UI, so the references themselves stay observation-ignored.
    @ObservationIgnored lazy var containers = ContainersStore(service: service, app: self)
    @ObservationIgnored lazy var dashboard = DashboardStore(service: service, app: self)
    @ObservationIgnored lazy var images = ImagesStore(service: service, app: self)
    @ObservationIgnored lazy var volumes = VolumesStore(service: service, app: self)
    @ObservationIgnored lazy var networks = NetworksStore(service: service, app: self)
    @ObservationIgnored lazy var system = SystemStore(service: service, app: self)
    @ObservationIgnored lazy var registries = RegistriesStore(service: service, app: self)
    @ObservationIgnored lazy var builds = BuildsStore(service: service, app: self)

    init(service: any ContainerServicing = ContainerService()) {
        self.service = service
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
