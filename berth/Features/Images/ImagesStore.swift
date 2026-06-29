//
//  ImagesStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class ImagesStore {
    var state: LoadState<[ContainerResource.ImageResource]> = .idle
    var actionError: String?
    var busy = false
    private var usage: [String: Int] = [:]   // image reference -> #containers

    private let service: ContainerService
    private unowned let app: AppModel

    init(service: ContainerService, app: AppModel) {
        self.service = service
        self.app = app
    }

    var all: [ContainerResource.ImageResource] { state.value ?? [] }

    func usedBy(_ image: ContainerResource.ImageResource) -> Int { usage[image.name] ?? 0 }

    func load() async {
        if case .idle = state { state = .loading }
        do {
            async let imagesCall = service.listImages()
            async let containersCall = service.listContainers()
            let images = try await imagesCall
            let containers = try await containersCall
            usage = containers.reduce(into: [:]) { $0[$1.configuration.image.reference, default: 0] += 1 }
            state = .loaded(images.sorted { $0.name < $1.name })
            app.counts[.images] = images.count
        } catch {
            state = .failed(Self.msg(error))
        }
    }

    func pull(reference: String) async {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return }
        await run { try await self.service.pullImage(reference: reference) }
    }

    func delete(_ reference: String) async {
        await run { try await self.service.deleteImage(reference: reference) }
    }

    func prune() async {
        await run { _ = try await self.service.pruneImageBlobs() }
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
