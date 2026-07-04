//
//  ContainerServicing.swift
//  berth
//
//  The service surface the per-screen stores (and EngineConnection) depend on.
//  `ContainerService` is the production conformance; the hermetic Layer-B store
//  tests substitute `FakeContainerService` (DebugSupport). Keep store-facing
//  service methods declared here so they stay fake-able.
//

import Foundation
import ContainerAPIClient
import ContainerResource

// MARK: - Service DTOs

/// Aggregate image usage for the Dashboard / System screens.
struct ImageSummary: Sendable {
    let count: Int
    let totalSize: UInt64
    let reclaimable: UInt64
}

/// Aggregate volume usage for the Dashboard / System screens.
struct VolumeSummary: Sendable {
    let count: Int
    let totalSize: UInt64
}

/// A coarse pull/unpack progress snapshot, accumulated from the engine's
/// `ProgressUpdateEvent` stream (delivered over an XPC endpoint).
struct PullProgress: Sendable {
    var phase = "Preparing…"
    var received: Int64 = 0
    var total: Int64 = 0
    /// 0...1 when a total is known; nil while indeterminate.
    var fraction: Double? { total > 0 ? min(1, Double(received) / Double(total)) : nil }
}

// MARK: - Protocol

nonisolated protocol ContainerServicing: Sendable {
    // System / health
    func health(timeout: Duration) async throws -> SystemHealth

    // Containers
    func listContainers() async throws -> [ContainerSnapshot]
    func startContainer(id: String) async throws
    func stopContainer(id: String) async throws
    func killContainer(id: String, signal: String) async throws
    func restartContainer(id: String) async throws
    func deleteContainer(id: String, force: Bool) async throws

    // Streaming
    func logStream(id: String) -> AsyncStream<LogLine>
    func stats(id: String) async throws -> ContainerStats

    // Aggregate summaries (Dashboard / System)
    func imageSummary(active: Set<String>) async throws -> ImageSummary
    func volumeSummary() async throws -> VolumeSummary

    // Images
    func listImages() async throws -> [ContainerResource.ImageResource]
    func pullImage(reference: String, progress: (@Sendable (PullProgress) -> Void)?) async throws
    func deleteImage(reference: String) async throws
    func pruneImageBlobs() async throws -> UInt64

    // Volumes
    func listVolumes() async throws -> [VolumeConfiguration]
    func createVolume(name: String, size: String?) async throws
    func deleteVolume(name: String) async throws

    // Networks
    func listNetworks() async throws -> [NetworkResource]
    func createNetwork(name: String) async throws
    func deleteNetwork(id: String) async throws

    // Registries (keychain-backed)
    func listRegistries() async throws -> [ContainerResource.RegistryResource]
    func loginRegistry(host: String, username: String, password: String) async throws
    func logoutRegistry(host: String) async throws

    // Builds — builder lifecycle
    func builderInfo() async throws -> BuilderInfo
    func startBuilder(progress: (@Sendable (PullProgress) -> Void)?) async throws
    func stopBuilder() async throws
    func deleteBuilder(force: Bool) async throws

    // Builds — execution. Like `logStream`: stream-shaped, cancellation via the
    // consuming task. Never throws — failures arrive as `.phase(.failed(_))`.
    func performBuild(_ request: BuildRequest) -> AsyncStream<BuildEvent>
}

// Protocols can't carry default arguments, so the call-site conveniences the
// concrete service offers live here for `any ContainerServicing` users.
nonisolated extension ContainerServicing {
    func health() async throws -> SystemHealth {
        try await health(timeout: .seconds(5))
    }

    func killContainer(id: String) async throws {
        try await killContainer(id: id, signal: "SIGKILL")
    }

    func startBuilder() async throws {
        try await startBuilder(progress: nil)
    }

    func deleteBuilder() async throws {
        try await deleteBuilder(force: false)
    }
}
