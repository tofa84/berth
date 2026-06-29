//
//  NetworksStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class NetworksStore {
    var state: LoadState<[NetworkResource]> = .idle
    var actionError: String?
    var busy = false
    private var usage: [String: Int] = [:]   // network name -> #containers

    private let service: ContainerService
    private unowned let app: AppModel

    init(service: ContainerService, app: AppModel) {
        self.service = service
        self.app = app
    }

    var all: [NetworkResource] { state.value ?? [] }

    func usedBy(_ network: NetworkResource) -> Int { usage[network.name] ?? 0 }

    /// The list narrowed by the global search query (name / subnet).
    func displayed(matching query: String) -> [NetworkResource] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q) || $0.subnetText.lowercased().contains(q)
        }
    }

    func load() async {
        if case .idle = state { state = .loading }
        do {
            async let networksCall = service.listNetworks()
            async let containersCall = service.listContainers()
            let networks = try await networksCall
            let containers = try await containersCall
            usage = [:]
            for c in containers {
                for attachment in c.networks { usage[attachment.network, default: 0] += 1 }
            }
            state = .loaded(networks.sorted { $0.name < $1.name })
            app.counts[.networks] = networks.count
        } catch {
            state = .failed(Self.msg(error))
        }
    }

    func create(name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await run { try await self.service.createNetwork(name: name) }
    }

    func delete(_ id: String) async {
        await run { try await self.service.deleteNetwork(id: id) }
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
