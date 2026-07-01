//
//  ContainersStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class ContainersStore: ResourceStore {
    enum Filter: String, CaseIterable, Hashable {
        case all = "All", running = "Running", stopped = "Stopped"
    }

    var filter: Filter = .all
    var state: LoadState<[ContainerSnapshot]> = .idle
    var selectedID: String?
    var actionError: String?
    var busyIDs: Set<String> = []
    /// In-flight flag for whole-list operations (prune); per-row work uses busyIDs.
    var busy = false

    private let service: any ContainerServicing
    private unowned let app: AppModel

    init(service: any ContainerServicing, app: AppModel) {
        self.service = service
        self.app = app
    }

    var filtered: [ContainerSnapshot] {
        switch filter {
        case .all: all
        case .running: all.filter { $0.status == .running }
        case .stopped: all.filter { $0.status != .running }
        }
    }

    /// The filtered list further narrowed by the global search query (id / image).
    func displayed(matching query: String) -> [ContainerSnapshot] {
        searchFiltered(query, in: filtered)
    }

    func matches(_ container: ContainerSnapshot, term: String) -> Bool {
        container.id.lowercased().contains(term)
            || container.imageReference.lowercased().contains(term)
    }

    var runningCount: Int { all.filter { $0.status == .running }.count }
    var totalCount: Int { all.count }
    /// Containers eligible for "Prune stopped" — anything not currently running.
    var stoppedCount: Int { all.filter { $0.status != .running }.count }

    var subtitle: String {
        "\(totalCount) total · \(runningCount) running · click a row to inspect"
    }

    func snapshot(_ id: String) -> ContainerSnapshot? { all.first { $0.id == id } }

    func load() async {
        beginLoading()
        do {
            // Through the shared feed: concurrent refreshes (dashboard tick)
            // ride the same fetch, and the feed owns the sidebar badge.
            let list = try await app.containersFeed.refresh()
            state = .loaded(list.sorted { $0.id < $1.id })
        } catch {
            state = .failed(Format.error(error))
        }
    }

    func start(_ id: String) async { await act(id) { try await self.service.startContainer(id: id) } }
    func stop(_ id: String) async { await act(id) { try await self.service.stopContainer(id: id) } }
    func kill(_ id: String) async { await act(id) { try await self.service.killContainer(id: id) } }
    func restart(_ id: String) async { await act(id) { try await self.service.restartContainer(id: id) } }

    func delete(_ id: String) async {
        await act(id) { try await self.service.deleteContainer(id: id, force: true) }
        if selectedID == id { selectedID = nil }
    }

    func pruneStopped() async {
        let stopped = all.filter { $0.status != .running }.map(\.id)
        await runPrune(noun: "containers", stopped.map { id in
            (id, { try await self.service.deleteContainer(id: id, force: true) })
        })
    }

    /// Per-row action bracket: like `runAction`, but holds the row's spinner
    /// (`busyIDs`) instead of the whole-list `busy` flag.
    private func act(_ id: String, _ work: () async throws -> Void) async {
        actionError = nil
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            try await work()
            await load()
        } catch {
            actionError = Format.error(error)
        }
    }
}
