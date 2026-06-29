//
//  ContainersStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class ContainersStore {
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

    private let service: ContainerService
    private unowned let app: AppModel

    init(service: ContainerService, app: AppModel) {
        self.service = service
        self.app = app
    }

    var all: [ContainerSnapshot] { state.value ?? [] }

    var filtered: [ContainerSnapshot] {
        switch filter {
        case .all: all
        case .running: all.filter { $0.status == .running }
        case .stopped: all.filter { $0.status != .running }
        }
    }

    /// The filtered list further narrowed by the global search query (id / image).
    func displayed(matching query: String) -> [ContainerSnapshot] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return filtered }
        return filtered.filter {
            $0.id.lowercased().contains(q) || $0.imageReference.lowercased().contains(q)
        }
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
        if case .idle = state { state = .loading }
        do {
            let list = try await service.listContainers()
            state = .loaded(list.sorted { $0.id < $1.id })
            app.counts[.containers] = list.count
        } catch {
            state = .failed(Self.msg(error))
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
        actionError = nil
        busy = true
        defer { busy = false }
        var failures: [String] = []
        for id in stopped {
            do { try await service.deleteContainer(id: id, force: true) }
            catch { failures.append("\(id): \(Self.msg(error))") }
        }
        actionError = pruneSummary(failures, of: stopped.count, noun: "containers")
        await load()
    }

    private func act(_ id: String, _ work: @escaping () async throws -> Void) async {
        actionError = nil
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            try await work()
            await load()
        } catch {
            actionError = Self.msg(error)
        }
    }

    private static func msg(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? "\(e)"
    }
}
