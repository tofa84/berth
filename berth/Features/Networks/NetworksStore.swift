//
//  NetworksStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class NetworksStore: ResourceStore {
    var state: LoadState<[NetworkResource]> = .idle
    var actionError: String?
    var busy = false
    private var usage: [String: Int] = [:]   // network name -> #containers

    private let service: any ContainerServicing
    private unowned let app: AppModel

    init(service: any ContainerServicing, app: AppModel) {
        self.service = service
        self.app = app
    }

    func usedBy(_ network: NetworkResource) -> Int { usage[network.name] ?? 0 }

    /// The list narrowed by the global search query (name / subnet).
    func displayed(matching query: String) -> [NetworkResource] {
        searchFiltered(query, in: all)
    }

    func matches(_ network: NetworkResource, term: String) -> Bool {
        network.name.lowercased().contains(term)
            || network.subnetText.lowercased().contains(term)
    }

    func load() async {
        beginLoading()
        do {
            async let networksCall = service.listNetworks()
            let containers = try await app.containersFeed.refresh()
            let networks = try await networksCall
            usage = [:]
            for c in containers {
                for attachment in c.networks { usage[attachment.network, default: 0] += 1 }
            }
            state = .loaded(networks.sorted { $0.name < $1.name })
            app.counts[.networks] = networks.count
        } catch {
            state = .failed(Format.error(error))
        }
    }

    func create(name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await runAction { try await self.service.createNetwork(name: name) }
    }

    func delete(_ id: String) async {
        await runAction { try await self.service.deleteNetwork(id: id) }
    }
}
