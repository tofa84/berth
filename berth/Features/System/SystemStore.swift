//
//  SystemStore.swift
//  berth
//
//  System screen: disk usage + engine lifecycle (start/stop/restart) via the
//  CLI. Engine version/paths come from EngineConnection's SystemHealth.
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class SystemStore {
    var imageSize: UInt64 = 0
    var volumeSize: UInt64 = 0
    var reclaimable: UInt64 = 0
    var busy = false
    var error: String?

    private let service: any ContainerServicing
    private unowned let app: AppModel

    init(service: any ContainerServicing, app: AppModel) {
        self.service = service
        self.app = app
    }

    func load() async {
        if let containers = try? await app.containersFeed.refresh() {
            let active = Set(containers.map { $0.configuration.image.reference })
            if let img = try? await service.imageSummary(active: active) {
                imageSize = img.totalSize
                reclaimable = img.reclaimable
            }
        }
        if let vol = try? await service.volumeSummary() {
            volumeSize = vol.totalSize
        }
    }

    func start() async { await act { try await SystemControl.start() } }
    func stop() async { await act { try await SystemControl.stop() } }
    func restart() async { await act { try await SystemControl.restart() } }

    func prune() async {
        await act { _ = try await self.service.pruneImageBlobs() }
        await load()
    }

    private func act(_ work: () async throws -> Void) async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await work()
            await app.engine.refresh()
        } catch {
            self.error = Format.error(error)
        }
    }
}
