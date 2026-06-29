//
//  UIModels.swift
//  berth
//
//  Presentation helpers over the engine's ContainerResource models. The library
//  models are already Sendable/Codable, so screens use them directly with these
//  computed accessors rather than maintaining parallel DTOs.
//

import SwiftUI
import ContainerResource
import ContainerizationOCI
import ContainerizationExtras

extension ContainerSnapshot: @retroactive Identifiable {}

extension ContainerSnapshot {
    var shortID: String { String(id.prefix(12)) }
    var imageReference: String { configuration.image.reference }
    var isRunning: Bool { status == .running }

    var portsSummary: String {
        let ports = configuration.publishedPorts
        guard !ports.isEmpty else { return "—" }
        return ports.map { "\($0.hostPort):\($0.containerPort)" }.joined(separator: ", ")
    }

    var primaryIP: String? {
        guard let cidr = networks.first?.ipv4Address.description else { return nil }
        return String(cidr.split(separator: "/").first ?? Substring(cidr))
    }

    var osArch: String {
        "\(configuration.platform.os)/\(configuration.platform.architecture)"
    }

    var allocatedCPUs: Int { configuration.resources.cpus }
    var memoryLimitBytes: UInt64 { configuration.resources.memoryInBytes }

    var command: String {
        let p = configuration.initProcess
        return ([p.executable] + p.arguments).joined(separator: " ")
    }

    /// Uptime only makes sense for a running container.
    var uptimeText: String { isRunning ? Format.uptime(since: startedDate) : "—" }
}

// MARK: - Images

extension ContainerResource.ImageResource: @retroactive Identifiable {}

extension ContainerResource.ImageResource {
    /// Split "docker.io/library/alpine:latest" into ("docker.io/library/alpine", "latest").
    private var refParts: (repo: String, tag: String) {
        let ref = name
        if let at = ref.firstIndex(of: "@") { return (String(ref[..<at]), "<none>") }
        if let colon = ref.lastIndex(of: ":"),
           !ref[ref.index(after: colon)...].contains("/") {
            return (String(ref[..<colon]), String(ref[ref.index(after: colon)...]))
        }
        return (ref, "latest")
    }

    var repository: String { refParts.repo }
    var tag: String { refParts.tag }
    var shortDigest: String {
        let d = variants.first?.digest ?? configuration.descriptor.digest
        return String(d.replacingOccurrences(of: "sha256:", with: "").prefix(12))
    }
    var platformsText: String {
        let ps = variants.map { "\($0.platform.os)/\($0.platform.architecture)" }
        return ps.isEmpty ? "—" : ps.joined(separator: ", ")
    }
    var totalSize: Int64 { variants.reduce(0) { $0 + $1.size } }
}

// MARK: - Volumes

extension VolumeConfiguration {
    var sizeText: String { Format.bytes(sizeInBytes) }
    var mountPoint: String { source }
}

// MARK: - Networks

extension NetworkResource: @retroactive Identifiable {}

extension NetworkResource {
    var driverLabel: String {
        configuration.plugin.replacingOccurrences(of: "container-network-", with: "")
    }
    var subnetText: String { String(status.ipv4Subnet.description) }
    var gatewayText: String { String(status.ipv4Gateway.description) }
}

// MARK: - Registries

extension ContainerResource.RegistryResource: @retroactive Identifiable {}

extension RuntimeStatus {
    var label: String { rawValue }

    var color: Color {
        switch self {
        case .running: Theme.green
        case .stopped: Theme.textMuted
        case .stopping: Theme.amber
        case .unknown: Theme.textFaint
        @unknown default: Theme.textFaint
        }
    }
}
