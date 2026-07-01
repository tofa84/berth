//
//  FakeContainerService.swift
//  berth
//
//  DEBUG-only scripted `ContainerServicing` conformance for the hermetic
//  Layer-B store tests: seed the resource arrays, script failures per
//  operation, and assert on the recorded calls. Lives in the app target next
//  to Fixtures for the same reason (tests must not link the container SPM
//  products).
//
//  `nonisolated` so its methods can witness the protocol's nonisolated
//  requirements; `@unchecked Sendable` is sound because tests and the
//  MainActor stores are the only clients — all access is single-threaded.
//

#if DEBUG
import Foundation
import ContainerAPIClient
import ContainerResource

/// A scripted failure with a stable user-facing message.
struct FakeServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

nonisolated final class FakeContainerService: ContainerServicing, @unchecked Sendable {
    // Seeded engine state. Delete operations remove from these arrays, so a
    // reload after a mutating action observes the change.
    var containers: [ContainerSnapshot] = []
    var images: [ContainerResource.ImageResource] = []
    var volumes: [VolumeConfiguration] = []
    var networks: [NetworkResource] = []
    var registries: [ContainerResource.RegistryResource] = []
    var scriptedLogs: [LogLine] = []
    var statsByID: [String: ContainerStats] = [:]
    var healthResult: SystemHealth?
    var imageSummaryResult = ImageSummary(count: 0, totalSize: 0, reclaimable: 0)
    var volumeSummaryResult = VolumeSummary(count: 0, totalSize: 0)
    var pruneBlobsFreed: UInt64 = 0

    /// Scripted failure messages, keyed like `calls` entries: either the full
    /// "op:key" (fail one target) or just "op" (fail the whole operation).
    var failures: [String: String] = [:]
    /// Scripted per-op suspensions, keyed by "op" — lets tests force two
    /// callers to overlap (e.g. the feed's single-flight dedup).
    var delays: [String: Duration] = [:]
    /// Every service call in order, recorded as "op" or "op:key".
    private(set) var calls: [String] = []

    func callCount(_ entry: String) -> Int { calls.filter { $0 == entry }.count }

    /// Recording is lock-protected: task-group fan-outs (the dashboard's
    /// stats fetch) call the fake from concurrent child tasks.
    private let lock = NSLock()

    private func record(_ op: String, _ key: String? = nil) throws {
        let entry = key.map { "\(op):\($0)" } ?? op
        let message: String? = lock.withLock {
            calls.append(entry)
            return failures[entry] ?? failures[op]
        }
        if let message { throw FakeServiceError(message: message) }
    }

    private func delayIfScripted(_ op: String) async {
        guard let delay = lock.withLock({ delays[op] }) else { return }
        try? await Task.sleep(for: delay)
    }

    // MARK: System / health

    func health(timeout: Duration) async throws -> SystemHealth {
        try record("health")
        guard let healthResult else { throw FakeServiceError(message: "health not scripted") }
        return healthResult
    }

    // MARK: Containers

    func listContainers() async throws -> [ContainerSnapshot] {
        await delayIfScripted("listContainers")
        try record("listContainers")
        return containers
    }

    func startContainer(id: String) async throws { try record("start", id) }
    func stopContainer(id: String) async throws { try record("stop", id) }
    func killContainer(id: String, signal: String) async throws { try record("kill", id) }
    func restartContainer(id: String) async throws { try record("restart", id) }

    func deleteContainer(id: String, force: Bool) async throws {
        try record("deleteContainer", id)
        containers.removeAll { $0.id == id }
    }

    // MARK: Streaming

    func logStream(id: String) -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            for line in scriptedLogs { continuation.yield(line) }
            continuation.finish()
        }
    }

    func stats(id: String) async throws -> ContainerStats {
        await delayIfScripted("stats")
        try record("stats", id)
        guard let stats = statsByID[id] else {
            throw FakeServiceError(message: "stats not scripted for \(id)")
        }
        return stats
    }

    // MARK: Aggregate summaries

    func imageSummary(active: Set<String>) async throws -> ImageSummary {
        try record("imageSummary")
        return imageSummaryResult
    }

    func volumeSummary() async throws -> VolumeSummary {
        try record("volumeSummary")
        return volumeSummaryResult
    }

    // MARK: Images

    func listImages() async throws -> [ContainerResource.ImageResource] {
        try record("listImages")
        return images
    }

    func pullImage(reference: String, progress: (@Sendable (PullProgress) -> Void)?) async throws {
        try record("pull", reference)
    }

    func deleteImage(reference: String) async throws {
        try record("deleteImage", reference)
        images.removeAll { $0.name == reference }
    }

    func pruneImageBlobs() async throws -> UInt64 {
        try record("pruneBlobs")
        return pruneBlobsFreed
    }

    // MARK: Volumes

    func listVolumes() async throws -> [VolumeConfiguration] {
        try record("listVolumes")
        return volumes
    }

    func createVolume(name: String, size: String?) async throws { try record("createVolume", name) }

    func deleteVolume(name: String) async throws {
        try record("deleteVolume", name)
        volumes.removeAll { $0.name == name }
    }

    // MARK: Networks

    func listNetworks() async throws -> [NetworkResource] {
        try record("listNetworks")
        return networks
    }

    func createNetwork(name: String) async throws { try record("createNetwork", name) }

    func deleteNetwork(id: String) async throws {
        try record("deleteNetwork", id)
        networks.removeAll { $0.id == id }
    }

    // MARK: Registries

    func listRegistries() async throws -> [ContainerResource.RegistryResource] {
        try record("listRegistries")
        return registries
    }

    func loginRegistry(host: String, username: String, password: String) async throws {
        try record("login", host)
    }

    func logoutRegistry(host: String) async throws {
        try record("logout", host)
        registries.removeAll { $0.name == host }
    }
}
#endif
