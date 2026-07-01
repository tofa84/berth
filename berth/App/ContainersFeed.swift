//
//  ContainersFeed.swift
//  berth
//
//  The single source for the engine's container list. Every consumer — the
//  Containers screen, the Dashboard tick, and the usage maps on the Images/
//  Volumes/Networks/System screens — refreshes through here, so concurrent
//  callers share one XPC round-trip (single-flight) and the sidebar badge
//  count has exactly one writer.
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class ContainersFeed {
    /// The most recently fetched list (unsorted, as delivered by the engine).
    private(set) var snapshots: [ContainerSnapshot] = []

    private let service: any ContainerServicing
    private unowned let app: AppModel
    @ObservationIgnored private var inflight: Task<[ContainerSnapshot], Error>?

    init(service: any ContainerServicing, app: AppModel) {
        self.service = service
        self.app = app
    }

    /// Fetch the current container list. Callers that arrive while a fetch is
    /// in flight await that same round-trip instead of issuing another. The
    /// fetch task itself publishes `snapshots`/badge, so the shared state is
    /// updated even if the caller that started it gets cancelled.
    @discardableResult
    func refresh() async throws -> [ContainerSnapshot] {
        if let inflight { return try await inflight.value }
        let task = Task { @MainActor in
            defer { self.inflight = nil }
            let list = try await self.service.listContainers()
            self.snapshots = list
            self.app.counts[.containers] = list.count
            return list
        }
        inflight = task
        return try await task.value
    }
}
