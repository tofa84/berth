//
//  BuildModels.swift
//  berth
//
//  berth-owned value types for the Builds screen. Deliberately free of any
//  apple/container SPM types so they can appear in `ContainerServicing`
//  signatures and be exercised by the hermetic Layer-B tests (which must not
//  link the container products). The service maps these to/from the engine
//  types behind the protocol seam.
//

import Foundation

/// Everything needed to start one image build. `Codable` so the history file
/// (M5) and re-run prefill can round-trip it.
struct BuildRequest: Sendable, Equatable, Codable {
    var contextDir: String
    var dockerfilePath: String
    var tags: [String]
    var buildArgs: [String]      // "KEY=VALUE"
    var labels: [String]         // "KEY=VALUE"
    var target: String
    var platforms: [String]      // "linux/arm64", "linux/amd64"
    var noCache: Bool
    var pull: Bool

    /// Upstream guard, see apple/container#735 — the shim rejects larger files.
    static let maxDockerfileBytes = 16 * 1024

    init(
        contextDir: String,
        dockerfilePath: String,
        tags: [String],
        buildArgs: [String] = [],
        labels: [String] = [],
        target: String = "",
        platforms: [String] = ["linux/arm64"],
        noCache: Bool = false,
        pull: Bool = false
    ) {
        self.contextDir = contextDir
        self.dockerfilePath = dockerfilePath
        self.tags = tags
        self.buildArgs = buildArgs
        self.labels = labels
        self.target = target
        self.platforms = platforms
        self.noCache = noCache
        self.pull = pull
    }
}

/// A snapshot of the buildkit builder container for the status card.
struct BuilderInfo: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case notCreated, stopped, running, stopping, unknown
    }
    var status: Status
    var imageReference: String?
    var cpus: Int?
    var memoryBytes: UInt64?

    static let notCreated = BuilderInfo(status: .notCreated)

    init(status: Status, imageReference: String? = nil, cpus: Int? = nil, memoryBytes: UInt64? = nil) {
        self.status = status
        self.imageReference = imageReference
        self.cpus = cpus
        self.memoryBytes = memoryBytes
    }
}

/// The coarse lifecycle phase of a build, for the activity header.
enum BuildPhase: Sendable, Equatable {
    case preparingBuilder(String)   // e.g. "Starting builder…"
    case building
    case importing(String)          // "Loading image", "Unpacking", "Tagging"
    case succeeded(tags: [String])
    case failed(message: String)

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed: return true
        case .preparingBuilder, .building, .importing: return false
        }
    }
}

/// One event from a running build. `performBuild` never throws — failures
/// arrive as `.phase(.failed(_))`, so the consumer has a single exhaustive
/// channel.
enum BuildEvent: Sendable {
    case phase(BuildPhase)
    case line(String)               // one plain-progress line from the shim
    case builderPull(PullProgress)  // reserved for a future native builder-start path
}

/// Failure that a build can surface beyond a thrown engine error.
enum BuildFailure: LocalizedError {
    case noOutput
    case rejectedArchive([String])
    case dockerfileTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .noOutput:
            return "Build produced no image."
        case .rejectedArchive(let members):
            return "Built archive contained invalid members: \(members.joined(separator: ", "))"
        case .dockerfileTooLarge(let bytes):
            return "Dockerfile is \(bytes) bytes; the builder rejects files ≥ \(BuildRequest.maxDockerfileBytes) bytes (apple/container#735)."
        }
    }
}
