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
        // Drop attestation manifests (platform `unknown/unknown`) and de-duplicate
        // (arm v6/v7 both report `linux/arm`) so the summary stays short and readable.
        var seen = Set<String>()
        let ps = variants
            .map { "\($0.platform.os)/\($0.platform.architecture)" }
            .filter { $0 != "unknown/unknown" && seen.insert($0).inserted }
        return ps.isEmpty ? "—" : ps.joined(separator: ", ")
    }
    var totalSize: Int64 { variants.reduce(0) { $0 + $1.size } }
    /// Full content digest (with the `sha256:` prefix), for copy actions.
    var fullDigest: String { variants.first?.digest ?? configuration.descriptor.digest }
    var isMultiArch: Bool { variants.count > 1 }

    /// Flattened, SwiftUI-friendly projection of each platform variant's OCI
    /// config + history. Built here (where ContainerizationOCI is imported) so the
    /// detail view can stay free of OCI types — which otherwise make `Image`/`State`
    /// ambiguous against SwiftUI.
    var variantInfos: [ImageVariantInfo] {
        // Hide attestation manifests (buildx provenance/SBOM, platform unknown/unknown);
        // they aren't runnable platforms and would clutter the picker and config view.
        let real = variants.filter { !($0.platform.os == "unknown" && $0.platform.architecture == "unknown") }
        return (real.isEmpty ? variants : real).enumerated().map { idx, v in
            let cfg = v.config
            let exec = cfg.config
            let layers = (cfg.history ?? []).enumerated().map { i, h in
                ImageLayerInfo(id: i, command: Self.cleanLayerCommand(h.createdBy),
                               created: h.created ?? "", empty: h.emptyLayer == true)
            }
            return ImageVariantInfo(
                id: idx,
                platform: v.platform.description,
                osArch: "\(cfg.os)/\(cfg.architecture)",
                entrypoint: Self.joinArgs(exec?.entrypoint),
                command: Self.joinArgs(exec?.cmd),
                user: Self.orDash(exec?.user),
                workingDir: Self.orDash(exec?.workingDir),
                stopSignal: Self.orDash(exec?.stopSignal),
                env: exec?.env ?? [],
                labels: (exec?.labels ?? [:]).sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) },
                layers: layers
            )
        }
    }

    private static func joinArgs(_ a: [String]?) -> String { (a?.isEmpty == false) ? a!.joined(separator: " ") : "—" }
    private static func orDash(_ s: String?) -> String { (s?.isEmpty == false) ? s! : "—" }
    /// Strip the noisy `/bin/sh -c #(nop) ` / `/bin/sh -c ` that Docker prepends.
    private static func cleanLayerCommand(_ raw: String?) -> String {
        guard var s = raw, !s.isEmpty else { return "—" }
        for p in ["/bin/sh -c #(nop) ", "/bin/sh -c "] where s.hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

/// A SwiftUI-ready view of one image platform variant (no OCI types leak out).
struct ImageVariantInfo: Identifiable {
    let id: Int
    let platform: String        // e.g. "linux/arm64/v8"
    let osArch: String          // e.g. "linux/arm64"
    let entrypoint: String
    let command: String
    let user: String
    let workingDir: String
    let stopSignal: String
    let env: [String]
    let labels: [(key: String, value: String)]
    let layers: [ImageLayerInfo]
}

struct ImageLayerInfo: Identifiable {
    let id: Int
    let command: String
    let created: String         // raw RFC3339 string, or "" if absent
    let empty: Bool
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
