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
    var pullProgress: ContainerService.PullProgress?

    private var usage: [String: Int] = [:]   // image reference -> #containers

    private let service: ContainerService
    private unowned let app: AppModel

    init(service: ContainerService, app: AppModel) {
        self.service = service
        self.app = app
    }

    var all: [ContainerResource.ImageResource] { state.value ?? [] }

    func usedBy(_ image: ContainerResource.ImageResource) -> Int { usage[image.name] ?? 0 }

    /// Images not referenced by any container (running or stopped) — the prune targets.
    var unusedCount: Int { all.filter { usedBy($0) == 0 }.count }

    func image(_ reference: String) -> ContainerResource.ImageResource? {
        all.first { $0.name == reference }
    }

    /// The list after applying the active search query, unused-only filter and sort.
    func displayed(matching query: String) -> [ContainerResource.ImageResource] {
        var list = all
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.shortDigest.lowercased().contains(q) }
        }
        if unusedOnly { list = list.filter { usedBy($0) == 0 } }
        switch sort {
        case .name: list.sort { $0.name < $1.name }
        case .size: list.sort { $0.totalSize > $1.totalSize }
        case .recent: list.sort { $0.creationDate > $1.creationDate }
        }
        return list
    }

    func load() async {
        if case .idle = state { state = .loading }
        do {
            async let imagesCall = service.listImages()
            async let containersCall = service.listContainers()
            let images = try await imagesCall
            let containers = try await containersCall
            usage = containers.reduce(into: [:]) { $0[$1.configuration.image.reference, default: 0] += 1 }
            state = .loaded(images)
            app.counts[.images] = images.count
        } catch {
            state = .failed(Self.msg(error))
        }
    }

    func pull(reference: String) async {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return }
        pullProgress = nil
        await run {
            try await self.service.pullImage(reference: reference) { p in
                Task { @MainActor in self.pullProgress = p }
            }
        }
        pullProgress = nil
    }

    func delete(_ reference: String) async {
        await run { try await self.service.deleteImage(reference: reference) }
        if selectedID == reference { selectedID = nil }
    }

    /// Remove every image not used by a container, then reclaim orphaned blobs.
    func prune() async {
        let unused = all.filter { usedBy($0) == 0 }.map(\.name)
        actionError = nil
        busy = true
        defer { busy = false }
        var failures: [String] = []
        for reference in unused {
            do { try await service.deleteImage(reference: reference) }
            catch { failures.append("\(reference): \(Self.msg(error))") }
        }
        // Sweep any content-store blobs left orphaned by the deletions.
        do { _ = try await service.pruneImageBlobs() }
        catch { failures.append("blobs: \(Self.msg(error))") }
        actionError = pruneSummary(failures, of: unused.count + 1, noun: "operations")
        if let sel = selectedID, unused.contains(sel) { selectedID = nil }
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
