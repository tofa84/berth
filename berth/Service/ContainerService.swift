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
import TerminalProgress

actor ContainerService: ContainerServicing {
    /// A fresh `ContainerClient` per call. Each one opens its own XPC connection
    /// (cancelled on deinit), mirroring how `ClientImage`/`ClientVolume`/
    /// `ClientHealthCheck` work. A single cached client would keep a long-lived
    /// connection that goes invalid when the engine restarts ("XPC connection
    /// error: Connection invalid"), wedging every container call until relaunch.
    private nonisolated func makeClient() -> ContainerClient { ContainerClient() }
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

    func listContainers() async throws -> [ContainerSnapshot] {
        // Exclude the helper "machine" containers, matching the CLI's `container list`.
        try await makeClient().list(filters: ContainerListFilters.all.withoutMachines())
    }

    func container(id: String) async throws -> ContainerSnapshot {
        try await makeClient().get(id: id)
    }

    /// Start a stopped container, detached (no host stdio attached; output goes
    /// to the container's log files). Mirrors `container start` (detached path).
    func startContainer(id: String) async throws {
        let client = makeClient()
        let snapshot = try await client.get(id: id)
        guard snapshot.status != .running else { return }
        let process = try await client.bootstrap(id: id, stdio: [nil, nil, nil])
        try await process.start()
    }

    func stopContainer(id: String) async throws {
        try await makeClient().stop(id: id)
    }

    func killContainer(id: String, signal: String = "SIGKILL") async throws {
        try await makeClient().kill(id: id, signal: signal)
    }

    func deleteContainer(id: String, force: Bool = false) async throws {
        try await makeClient().delete(id: id, force: force)
    }

    func restartContainer(id: String) async throws {
        let client = makeClient()
        // Tolerate "already stopped" (a benign stop failure on a non-running
        // container), but surface a real stop failure: if stop threw *and* the
        // container is still running, the restart genuinely didn't happen.
        let stopError: Error?
        do { try await client.stop(id: id); stopError = nil }
        catch { stopError = error }
        let snapshot = try await client.get(id: id)
        if snapshot.status == .running, let stopError { throw stopError }
        try await startContainer(id: id)
    }

    // MARK: Streaming

    /// A live stream of the container's stdout/stderr log lines. The reading
    /// happens off the main actor; cancelling the consuming task tears it down.
    nonisolated func logStream(id: String) -> AsyncStream<LogLine> {
        let client = makeClient()
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
        try await makeClient().stats(id: id)
    }

    // MARK: Aggregate summaries (Dashboard)

    func imageSummary(active: Set<String>) async throws -> ImageSummary {
        let images = try await ClientImage.list()
        let du = try await ClientImage.calculateDiskUsage(activeReferences: active)
        return ImageSummary(count: images.count, totalSize: du.totalSize, reclaimable: du.reclaimableSize)
    }

    func volumeSummary() async throws -> VolumeSummary {
        let volumes = try await ClientVolume.list()
        // Query per-volume disk usage concurrently — one serial XPC round-trip
        // per volume would make this O(n) in latency on volume-heavy setups.
        let total = await withTaskGroup(of: UInt64.self) { group in
            for volume in volumes {
                let name = volume.name
                group.addTask { (try? await ClientVolume.volumeDiskUsage(name: name)) ?? 0 }
            }
            return await group.reduce(0, +)
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

    /// Thread-safe accumulator: the engine calls the handler concurrently, so the
    /// running totals live behind an actor and each batch returns a fresh snapshot.
    private actor PullProgressState {
        private var p = PullProgress()
        func apply(_ events: [ProgressUpdateEvent]) -> PullProgress {
            for e in events {
                switch e {
                case .setDescription(let s), .setSubDescription(let s): p.phase = s
                case .setTotalSize(let v): p.total = v
                case .addTotalSize(let v): p.total += v
                case .setSize(let v): p.received = v
                case .addSize(let v): p.received += v
                default: break
                }
            }
            return p
        }
    }

    func pullImage(reference: String, progress: (@Sendable (PullProgress) -> Void)? = nil) async throws {
        let cfg = try await config()
        let normalized = try ClientImage.normalizeReference(reference, containerSystemConfig: cfg)

        var handler: ProgressUpdateHandler?
        if let progress {
            let state = PullProgressState()
            handler = { events in progress(await state.apply(events)) }
        }

        let image = try await ClientImage.pull(reference: normalized, containerSystemConfig: cfg, progressUpdate: handler)
        // Let unpack failures (disk full, missing platform variant, …) surface to
        // the UI — a "pulled" image that didn't unpack only fails later at run.
        try await image.unpack(platform: nil, progressUpdate: handler)
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
