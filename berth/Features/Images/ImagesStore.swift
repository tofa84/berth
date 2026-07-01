//
//  ImagesStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class ImagesStore: ResourceStore {
    enum Sort: String, CaseIterable, Hashable {
        case name = "Name", size = "Largest", recent = "Newest"
    }

    var state: LoadState<[ContainerResource.ImageResource]> = .idle
    var actionError: String?
    var busy = false

    /// Selected image (by reference/name) for the master/detail view; nil = list.
    var selectedID: String?
    var sort: Sort = .name
    var unusedOnly = false
    /// Live progress while a pull is in flight (nil when idle/indeterminate-done).
    var pullProgress: PullProgress?

    private var usage: [String: Int] = [:]   // image reference -> #containers

    private let service: any ContainerServicing
    private unowned let app: AppModel

    init(service: any ContainerServicing, app: AppModel) {
        self.service = service
        self.app = app
    }

    func usedBy(_ image: ContainerResource.ImageResource) -> Int { usage[image.name] ?? 0 }

    /// Images not referenced by any container (running or stopped) — the prune targets.
    var unusedCount: Int { all.filter { usedBy($0) == 0 }.count }

    func image(_ reference: String) -> ContainerResource.ImageResource? {
        all.first { $0.name == reference }
    }

    /// The list after applying the active search query, unused-only filter and sort.
    func displayed(matching query: String) -> [ContainerResource.ImageResource] {
        var list = searchFiltered(query, in: all)
        if unusedOnly { list = list.filter { usedBy($0) == 0 } }
        switch sort {
        case .name: list.sort { $0.name < $1.name }
        case .size: list.sort { $0.totalSize > $1.totalSize }
        case .recent: list.sort { $0.creationDate > $1.creationDate }
        }
        return list
    }

    func matches(_ image: ContainerResource.ImageResource, term: String) -> Bool {
        image.name.lowercased().contains(term)
            || image.shortDigest.lowercased().contains(term)
    }

    func load() async {
        beginLoading()
        do {
            async let imagesCall = service.listImages()
            async let containersCall = service.listContainers()
            let images = try await imagesCall
            let containers = try await containersCall
            usage = containers.reduce(into: [:]) { $0[$1.configuration.image.reference, default: 0] += 1 }
            state = .loaded(images)
            app.counts[.images] = images.count
        } catch {
            state = .failed(Format.error(error))
        }
    }

    func pull(reference: String) async {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return }
        pullProgress = nil
        await runAction {
            try await self.service.pullImage(reference: reference) { p in
                Task { @MainActor in self.pullProgress = p }
            }
        }
        pullProgress = nil
    }

    func delete(_ reference: String) async {
        await runAction { try await self.service.deleteImage(reference: reference) }
        if selectedID == reference { selectedID = nil }
    }

    /// Remove every image not used by a container, then reclaim orphaned blobs.
    func prune() async {
        let unused = all.filter { usedBy($0) == 0 }.map(\.name)
        var operations: [(label: String, run: () async throws -> Void)] = unused.map { reference in
            (reference, { try await self.service.deleteImage(reference: reference) })
        }
        // Sweep any content-store blobs left orphaned by the deletions.
        operations.append(("blobs", { _ = try await self.service.pruneImageBlobs() }))
        await runPrune(noun: "operations", operations)
        if let sel = selectedID, unused.contains(sel) { selectedID = nil }
    }
}
