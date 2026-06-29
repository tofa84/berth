//
//  ContainerService.swift
//  berth
//
//  The single gateway to the apple/container engine. An `actor`, so all XPC
//  I/O and JSON decode/map happen off the main actor; methods return Sendable
//  values that MainActor stores consume. Grows one method group per phase.
//

import Foundation
import ContainerAPIClient
import ContainerResource
import ContainerPersistence
import ContainerizationOCI
import ContainerizationOS

actor ContainerService {
    private let client = ContainerClient()
    private var _config: ContainerSystemConfig?

    /// The engine's system configuration (registry/dns defaults), loaded once.
    private func config() async throws -> ContainerSystemConfig {
        if let c = _config { return c }
        let c = try await ConfigurationLoader.load()
        _config = c
        return c
    }

    // MARK: System / health

    func health(timeout: Duration = .seconds(5)) async throws -> SystemHealth {
        try await ClientHealthCheck.ping(timeout: timeout)
    }

    // MARK: Containers

    func listContainers(filters: ContainerListFilters = .all) async throws -> [ContainerSnapshot] {
        // Exclude the helper "machine" containers, matching the CLI's `container list`.
        try await client.list(filters: filters.withoutMachines())
    }

    func container(id: String) async throws -> ContainerSnapshot {
        try await client.get(id: id)
    }

    /// Start a stopped container, detached (no host stdio attached; output goes
    /// to the container's log files). Mirrors `container start` (detached path).
    func startContainer(id: String) async throws {
        let snapshot = try await client.get(id: id)
        guard snapshot.status != .running else { return }
        let process = try await client.bootstrap(id: id, stdio: [nil, nil, nil])
        try await process.start()
    }

    func stopContainer(id: String) async throws {
        try await client.stop(id: id)
    }

    func killContainer(id: String, signal: String = "SIGKILL") async throws {
        try await client.kill(id: id, signal: signal)
    }

    func deleteContainer(id: String, force: Bool = false) async throws {
        try await client.delete(id: id, force: force)
    }

    func restartContainer(id: String) async throws {
        try? await client.stop(id: id)
        try await startContainer(id: id)
    }

    // MARK: Streaming

    /// A live stream of the container's stdout/stderr log lines. The reading
    /// happens off the main actor; cancelling the consuming task tears it down.
    nonisolated func logStream(id: String) -> AsyncStream<LogLine> {
        let client = self.client
        return AsyncStream { continuation in
            let task = Task {
                do {
                    let handles = try await client.logs(id: id)
                    // Lets the reader stop polling once the container exits (a
                    // stopped container's log file sits at EOF forever otherwise).
                    let isStopped: @Sendable () async -> Bool = {
                        guard let snap = try? await client.get(id: id) else { return false }
                        return snap.status != .running
                    }
                    await LogReader.pump(handles, isStopped: isStopped, into: continuation)
                } catch {
                    continuation.yield(LogLine(text: "failed to open logs: \(error)", kind: .stderr))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stats(id: String) async throws -> ContainerStats {
        try await client.stats(id: id)
    }

    // MARK: Aggregate summaries (Dashboard)

    struct ImageSummary: Sendable { let count: Int; let totalSize: UInt64; let reclaimable: UInt64 }
    struct VolumeSummary: Sendable { let count: Int; let totalSize: UInt64 }

    func imageSummary(active: Set<String>) async throws -> ImageSummary {
        let images = try await ClientImage.list()
        let du = try await ClientImage.calculateDiskUsage(activeReferences: active)
        return ImageSummary(count: images.count, totalSize: du.totalSize, reclaimable: du.reclaimableSize)
    }

    func volumeSummary() async throws -> VolumeSummary {
        let volumes = try await ClientVolume.list()
        var total: UInt64 = 0
        for v in volumes {
            total += (try? await ClientVolume.volumeDiskUsage(name: v.name)) ?? 0
        }
        return VolumeSummary(count: volumes.count, totalSize: total)
    }

    // MARK: Images

    func listImages() async throws -> [ContainerResource.ImageResource] {
        let cfg = try await config()
        let images = try await ClientImage.list()
        var out: [ContainerResource.ImageResource] = []
        for img in images {
            if let r = try? await img.toImageResource(containerSystemConfig: cfg) { out.append(r) }
        }
        return out
    }

    func pullImage(reference: String) async throws {
        let cfg = try await config()
        let normalized = try ClientImage.normalizeReference(reference, containerSystemConfig: cfg)
        let image = try await ClientImage.pull(reference: normalized, containerSystemConfig: cfg)
        // Let unpack failures (disk full, missing platform variant, …) surface to
        // the UI — a "pulled" image that didn't unpack only fails later at run.
        try await image.unpack(platform: nil)
    }

    func deleteImage(reference: String) async throws {
        try await ClientImage.delete(reference: reference, garbageCollect: true)
    }

    func tagImage(source: String, target: String) async throws {
        let cfg = try await config()
        let existing = try await ClientImage.get(reference: source, containerSystemConfig: cfg)
        let normalizedTarget = try ClientImage.normalizeReference(target, containerSystemConfig: cfg)
        _ = try await existing.tag(new: normalizedTarget)
    }

    /// Reclaim orphaned image blobs; returns bytes freed.
    @discardableResult
    func pruneImageBlobs() async throws -> UInt64 {
        let (_, size) = try await ClientImage.cleanUpOrphanedBlobs()
        return size
    }

    // MARK: Volumes

    func listVolumes() async throws -> [VolumeConfiguration] {
        try await ClientVolume.list()
    }

    func createVolume(name: String, size: String?) async throws {
        var opts: [String: String] = [:]
        if let size, !size.isEmpty { opts["size"] = size }
        _ = try await ClientVolume.create(name: name, driverOpts: opts)
    }

    func deleteVolume(name: String) async throws {
        try await ClientVolume.delete(name: name)
    }

    // MARK: Networks

    func listNetworks() async throws -> [NetworkResource] {
        try await NetworkClient().list()
    }

    func createNetwork(name: String) async throws {
        let cfg = try NetworkConfiguration(name: name, mode: .nat, plugin: "container-network-vmnet")
        _ = try await NetworkClient().create(configuration: cfg)
    }

    func deleteNetwork(id: String) async throws {
        try await NetworkClient().delete(id: id)
    }

    // MARK: Registries (keychain-backed)

    func listRegistries() async throws -> [ContainerResource.RegistryResource] {
        let keychain = KeychainHelper(securityDomain: Constants.keychainID)
        return try keychain.list().map { ContainerResource.RegistryResource(from: $0) }
    }

    func loginRegistry(host: String, username: String, password: String) async throws {
        let keychain = KeychainHelper(securityDomain: Constants.keychainID)
        try keychain.save(hostname: host, username: username, password: password)
    }

    func logoutRegistry(host: String) async throws {
        let keychain = KeychainHelper(securityDomain: Constants.keychainID)
        try keychain.delete(hostname: host)
    }
}
