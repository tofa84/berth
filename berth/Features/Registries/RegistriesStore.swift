//
//  RegistriesStore.swift
//  berth
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class RegistriesStore {
    var state: LoadState<[ContainerResource.RegistryResource]> = .idle
    var actionError: String?
    var busy = false

    private let service: ContainerService
    private unowned let app: AppModel

    init(service: ContainerService, app: AppModel) {
        self.service = service
        self.app = app
    }

    var all: [ContainerResource.RegistryResource] { state.value ?? [] }

    /// The list narrowed by the global search query (host / username).
    func displayed(matching query: String) -> [ContainerResource.RegistryResource] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q) || $0.username.lowercased().contains(q)
        }
    }

    func load() async {
        if case .idle = state { state = .loading }
        do {
            let regs = try await service.listRegistries()
            state = .loaded(regs.sorted { $0.name < $1.name })
        } catch {
            state = .failed(Self.msg(error))
        }
    }

    func login(host: String, username: String, password: String) async -> Bool {
        await run { try await self.service.loginRegistry(host: host, username: username, password: password) }
    }

    func logout(_ host: String) async {
        _ = await run { try await self.service.logoutRegistry(host: host) }
    }

    @discardableResult
    private func run(_ work: @escaping () async throws -> Void) async -> Bool {
        actionError = nil
        busy = true
        defer { busy = false }
        do { try await work(); await load(); return true }
        catch { actionError = Self.msg(error); return false }
    }

    private static func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
}
