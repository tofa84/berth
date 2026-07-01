//
//  RegistriesStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class RegistriesStore: ResourceStore {
    var state: LoadState<[ContainerResource.RegistryResource]> = .idle
    var actionError: String?
    var busy = false

    private let service: any ContainerServicing
    private unowned let app: AppModel

    init(service: any ContainerServicing, app: AppModel) {
        self.service = service
        self.app = app
    }

    /// The list narrowed by the global search query (host / username).
    func displayed(matching query: String) -> [ContainerResource.RegistryResource] {
        searchFiltered(query, in: all)
    }

    func matches(_ registry: ContainerResource.RegistryResource, term: String) -> Bool {
        registry.name.lowercased().contains(term)
            || registry.username.lowercased().contains(term)
    }

    func load() async {
        beginLoading()
        do {
            let regs = try await service.listRegistries()
            state = .loaded(regs.sorted { $0.name < $1.name })
        } catch {
            state = .failed(Format.error(error))
        }
    }

    func login(host: String, username: String, password: String) async -> Bool {
        await runAction { try await self.service.loginRegistry(host: host, username: username, password: password) }
    }

    func logout(_ host: String) async {
        await runAction { try await self.service.logoutRegistry(host: host) }
    }
}
