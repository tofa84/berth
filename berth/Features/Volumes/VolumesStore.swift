//
//  VolumesStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class VolumesStore {
    var state: LoadState<[VolumeConfiguration]> = .idle
    var actionError: String?
    var busy = false
    private var usage: [String: Int] = [:]   // volume name -> #containers

    private let service: ContainerService
    private unowned let app: AppModel

    init(service: ContainerService, app: AppModel) {
        self.service = service
        self.app = app
    }

    var all: [VolumeConfiguration] { state.value ?? [] }
    var anonymousCount: Int { all.filter { $0.isAnonymous }.count }

    func usedBy(_ volume: VolumeConfiguration) -> Int { usage[volume.name] ?? 0 }

    func load() async {
        if case .idle = state { state = .loading }
        do {
            async let volumesCall = service.listVolumes()
            async let containersCall = service.listContainers()
            let volumes = try await volumesCall
            let containers = try await containersCall
            usage = [:]
            for c in containers {
                for m in c.configuration.mounts {
                    if let name = m.volumeName { usage[name, default: 0] += 1 }
                }
            }
            state = .loaded(volumes.sorted { $0.name < $1.name })
            app.counts[.volumes] = volumes.count
        } catch {
            state = .failed(Self.msg(error))
        }
    }

    func create(name: String, size: String?) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await run { try await self.service.createVolume(name: name, size: size) }
    }

    func delete(_ name: String) async {
        await run { try await self.service.deleteVolume(name: name) }
    }

    func prune() async {
        let unused = all.filter { usage[$0.name] ?? 0 == 0 }.map(\.name)
        actionError = nil
        busy = true
        defer { busy = false }
        for name in unused {
            do { try await service.deleteVolume(name: name) }
            catch { actionError = Self.msg(error) }
        }
        await load()
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        actionError = nil
        busy = true
        defer { busy = false }
        do { try await work(); await load() }
        catch { actionError = Self.msg(error) }
    }

    private static func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
}
