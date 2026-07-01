//
//  Fixtures.swift
//  berth
//
//  DEBUG-only factory helpers that build the apple/container `ContainerResource`
//  view-model types via their public initializers (no engine, no JSON). They live
//  in the app target — not the test target — so `berthTests` never has to link the
//  container SPM products itself (which would flip the whole package graph to
//  dynamic frameworks and break the build). Tests reach them via `@testable import
//  berth` and only touch berth-declared accessors, so no test file imports
//  ContainerResource. Compiled out of Release builds.
//

#if DEBUG
import Foundation
import ContainerResource
import ContainerizationOCI
import ContainerizationExtras

enum Fixtures {

    // MARK: - Containers

    /// A `ContainerSnapshot` with just enough shape to exercise the UIModels
    /// accessors. `id` feeds `shortID`; `ipv4` (a CIDR like "10.0.0.2/24") feeds
    /// `primaryIP`; `ports` feed `portsSummary`.
    static func snapshot(
        id: String = "abcdef0123456789aaaa",
        image: String = "docker.io/library/nginx:latest",
        ports: [(host: UInt16, container: UInt16, udp: Bool)] = [],
        os: String = "linux",
        arch: String = "arm64",
        cpus: Int = 2,
        memBytes: UInt64 = 1 << 30,
        exec: String = "/bin/sh",
        args: [String] = [],
        running: Bool = true,
        ipv4: String? = nil,
        gateway: String = "192.168.64.1",
        started: Date? = nil,
        volumeMounts: [(volume: String, destination: String)] = []
    ) throws -> ContainerSnapshot {
        let descriptor = Descriptor(
            mediaType: "application/vnd.oci.image.index.v1+json",
            digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
            size: 0)
        var cfg = ContainerConfiguration(
            id: id,
            image: ImageDescription(reference: image, descriptor: descriptor),
            process: ProcessConfiguration(executable: exec, arguments: args, environment: []))
        cfg.platform = Platform(arch: arch, os: os)
        var resources = ContainerConfiguration.Resources()
        resources.cpus = cpus
        resources.memoryInBytes = memBytes
        cfg.resources = resources
        cfg.mounts = volumeMounts.map {
            Filesystem.volume(
                name: $0.volume, format: "ext4",
                source: "/vols/\($0.volume)", destination: $0.destination, options: [])
        }
        cfg.publishedPorts = try ports.map {
            try PublishPort(
                hostAddress: try IPAddress("0.0.0.0"),
                hostPort: $0.host, containerPort: $0.container,
                proto: $0.udp ? .udp : .tcp, count: 1)
        }
        var networks: [Attachment] = []
        if let ipv4 {
            networks.append(Attachment(
                network: "default", hostname: "test",
                ipv4Address: try CIDRv4(ipv4),
                ipv4Gateway: try IPv4Address(gateway),
                ipv6Address: nil, macAddress: nil))
        }
        return ContainerSnapshot(
            configuration: cfg, status: running ? .running : .stopped,
            networks: networks, startedDate: started)
    }

    // MARK: - Images

    /// One image platform variant description for `image(...)`.
    struct VariantSpec {
        var os: String = "linux"
        var arch: String = "arm64"
        var variant: String? = "v8"
        var digest: String = "sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        var size: Int64 = 100
    }

    /// One flattened history entry for a variant (drives `variantInfos.layers`).
    struct LayerSpec {
        var createdBy: String?
        var created: String? = "2024-01-01T00:00:00Z"
        var empty: Bool? = false
    }

    static func image(
        name: String = "docker.io/library/alpine:latest",
        variants: [VariantSpec] = [VariantSpec()],
        layers: [LayerSpec] = [],
        entrypoint: [String]? = nil,
        cmd: [String]? = nil,
        user: String? = nil,
        workingDir: String? = nil,
        stopSignal: String? = nil,
        env: [String]? = nil,
        labels: [String: String]? = nil
    ) -> ContainerResource.ImageResource {
        let indexDescriptor = Descriptor(
            mediaType: "application/vnd.oci.image.index.v1+json",
            digest: variants.first?.digest ?? "sha256:index",
            size: 0)
        let configuration = ContainerResource.ImageResource.ImageConfiguration(
            description: ImageDescription(reference: name, descriptor: indexDescriptor),
            creationDate: Date())

        let history = layers.map {
            History(created: $0.created, createdBy: $0.createdBy, emptyLayer: $0.empty)
        }
        let ociVariants = variants.map { v -> ContainerResource.ImageResource.Variant in
            let ociImage = ContainerizationOCI.Image(
                architecture: v.arch,
                os: v.os,
                variant: v.variant,
                config: ImageConfig(
                    user: user, env: env, entrypoint: entrypoint, cmd: cmd,
                    workingDir: workingDir, labels: labels, stopSignal: stopSignal),
                rootfs: Rootfs(type: "layers", diffIDs: []),
                history: history.isEmpty ? nil : history)
            return ContainerResource.ImageResource.Variant(
                platform: Platform(arch: v.arch, os: v.os, variant: v.variant),
                digest: v.digest, size: v.size, config: ociImage)
        }
        return ContainerResource.ImageResource(configuration: configuration, variants: ociVariants)
    }

    // MARK: - Volumes

    static func volume(
        name: String = "data",
        source: String = "/var/lib/containerization/volumes/data",
        sizeInBytes: UInt64? = nil
    ) -> VolumeConfiguration {
        VolumeConfiguration(name: name, source: source, sizeInBytes: sizeInBytes)
    }

    // MARK: - Stats

    static func stats(
        id: String = "abc",
        memoryUsage: UInt64? = nil,
        memoryLimit: UInt64? = nil,
        cpuUsageUsec: UInt64? = nil,
        networkRx: UInt64? = nil,
        networkTx: UInt64? = nil,
        processes: UInt64? = nil
    ) -> ContainerStats {
        ContainerStats(
            id: id,
            memoryUsageBytes: memoryUsage, memoryLimitBytes: memoryLimit,
            cpuUsageUsec: cpuUsageUsec,
            networkRxBytes: networkRx, networkTxBytes: networkTx,
            blockReadBytes: nil, blockWriteBytes: nil,
            numProcesses: processes)
    }

    // MARK: - Registries

    static func registry(
        host: String = "ghcr.io",
        username: String = "octocat"
    ) -> ContainerResource.RegistryResource {
        ContainerResource.RegistryResource(
            hostname: host, username: username,
            creationDate: Date(), modificationDate: Date())
    }

    // MARK: - Networks

    static func network(
        name: String = "default",
        plugin: String = "container-network-vmnet",
        subnet: String = "192.168.64.0/24",
        gateway: String = "192.168.64.1"
    ) throws -> NetworkResource {
        let configuration = try NetworkConfiguration(name: name, mode: .nat, plugin: plugin)
        let status = NetworkStatus(
            ipv4Subnet: try CIDRv4(subnet),
            ipv4Gateway: try IPv4Address(gateway),
            ipv6Subnet: nil)
        return NetworkResource(configuration: configuration, status: status)
    }
}
#endif
