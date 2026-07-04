//
//  ContainerService+Build.swift
//  berth
//
//  The Builds service surface on the production `ContainerService` actor.
//  The build itself is native gRPC (via the vendored `BuildRunner`); only the
//  buildkit VM lifecycle shells out to `container builder …` (see the
//  builder-lifecycle memo — rebuilding its config natively needs the
//  non-linkable Parser.resources and is fragile across engine versions).
//

import Foundation
import ContainerAPIClient
import ContainerBuild
import ContainerImagesServiceClient
import ContainerizationOCI
import ContainerizationOS
import ContainerResource
import Logging

extension ContainerService {
    private static let builderID = "buildkit"
    private static let builderVsockPort: UInt32 = 8088
    private static let builderResourceDir = "builder"

    // MARK: Builder lifecycle

    func builderInfo() async throws -> BuilderInfo {
        do {
            let snapshot = try await makeClient().get(id: Self.builderID)
            let status: BuilderInfo.Status
            switch snapshot.status {
            case .running: status = .running
            case .stopped: status = .stopped
            case .stopping: status = .stopping
            default: status = .unknown
            }
            return BuilderInfo(
                status: status,
                imageReference: snapshot.configuration.image.reference,
                cpus: snapshot.configuration.resources.cpus,
                memoryBytes: snapshot.configuration.resources.memoryInBytes)
        } catch {
            // No buildkit container (or unreachable). The engine-down case is
            // handled separately by the screen's engine gate.
            return .notCreated
        }
    }

    func startBuilder(progress: (@Sendable (PullProgress) -> Void)?) async throws {
        _ = try await SystemControl.container(["builder", "start"])
    }

    func stopBuilder() async throws {
        _ = try await SystemControl.container(["builder", "stop"])
    }

    func deleteBuilder(force: Bool) async throws {
        _ = try await SystemControl.container(["builder", "delete"] + (force ? ["--force"] : []))
    }

    // MARK: Build execution

    nonisolated func performBuild(_ request: BuildRequest) -> AsyncStream<BuildEvent> {
        AsyncStream { continuation in
            let task = Task {
                let emit: @Sendable (BuildEvent) -> Void = { continuation.yield($0) }
                guard await self.acquireBuild() else {
                    emit(.phase(.failed(message: "A build is already running")))
                    continuation.finish()
                    return
                }
                do {
                    try await self.runBuild(request, emit: emit)
                } catch is CancellationError {
                    emit(.phase(.cancelled))
                } catch {
                    emit(.phase(.failed(message: Format.error(error))))
                }
                await self.releaseBuild()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func acquireBuild() -> Bool {
        if buildInFlight { return false }
        buildInFlight = true
        return true
    }

    private func releaseBuild() {
        buildInFlight = false
    }

    /// The full build: validate → ensure/dial builder → run (native gRPC, plain
    /// progress into a pipe) → import (load/unpack/tag). Throws on failure; the
    /// caller turns that into a `.phase(.failed(_))` event.
    private nonisolated func runBuild(
        _ request: BuildRequest,
        emit: @escaping @Sendable (BuildEvent) -> Void
    ) async throws {
        let fm = FileManager.default

        // 1. Read + validate the Dockerfile (+ optional sibling .dockerignore).
        let dockerfileData = try Data(contentsOf: URL(fileURLWithPath: request.dockerfilePath))
        guard dockerfileData.count < BuildRequest.maxDockerfileBytes else {
            throw BuildFailure.dockerfileTooLarge(dockerfileData.count)
        }
        let dockerignoreData = try? Data(contentsOf: URL(fileURLWithPath: request.dockerfilePath + ".dockerignore"))

        // 2. Normalize tags + parse platforms (berth strings → engine types).
        let tags = try request.tags.map { raw -> String in
            let ref = try Reference.parse(raw)
            ref.normalize()
            return ref.description
        }
        let platforms = try request.platforms.map { try Platform(from: $0) }

        // 3. Ensure the builder is up, then dial it (native gRPC).
        let cfg = try await self.config()
        let runner = try await dialBuilder(emit: emit)

        // 4. Export dir under appRoot/builder/<buildID> (virtiofs-mounted into the VM).
        let health = try await ClientHealthCheck.ping(timeout: .seconds(10))
        let buildID = UUID().uuidString
        let exportDir = health.appRoot
            .appendingPathComponent(Self.builderResourceDir)
            .appendingPathComponent(buildID)
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let outTar = exportDir.appendingPathComponent("out.tar")

        // 5. Pipe-backed Terminal so plain progress lands in a handle we own.
        //    Capture only the fd (Sendable) into the reader task, not the handle.
        let pipe = Pipe()
        let readFD = pipe.fileHandleForReading.fileDescriptor
        let terminal = try Terminal(
            descriptor: pipe.fileHandleForWriting.fileDescriptor, setInitState: false)
        let reader = Task {
            let handle = FileHandle(fileDescriptor: readFD, closeOnDealloc: false)
            do {
                for try await line in handle.bytes.lines {
                    emit(.line(line))
                }
            } catch {
                // read end closed / build torn down — nothing to surface here.
            }
        }

        let export = Builder.BuildExport(
            type: "oci", destination: outTar, additionalFields: [:], rawValue: "type=oci")
        let config = Builder.BuildConfig(
            buildID: buildID,
            contentStore: RemoteContentStoreClient(),
            buildArgs: request.buildArgs,
            secrets: [:],
            contextDir: request.contextDir,
            dockerfile: dockerfileData,
            dockerignore: dockerignoreData,
            labels: request.labels,
            noCache: request.noCache,
            platforms: platforms,
            terminal: terminal,
            tags: tags,
            target: request.target,
            quiet: false,
            exports: [export],
            cacheIn: [],
            cacheOut: [],
            pull: request.pull,
            containerSystemConfig: cfg)

        // 6. Run, then ALWAYS drain the pipe + tear the runner down.
        emit(.phase(.building))
        var runError: Error?
        do {
            try await runner.run(config)
        } catch {
            runError = error
        }
        try? pipe.fileHandleForWriting.close()  // EOF for the reader
        _ = await reader.value
        await runner.shutdown()

        if let runError {
            try? fm.removeItem(at: exportDir)
            throw runError
        }

        // 7. Import the built image (load → unpack → tag), then clean up.
        do {
            try await importBuiltImage(outTar: outTar, tags: tags, emit: emit)
        } catch {
            try? fm.removeItem(at: exportDir)
            throw error
        }
        try? fm.removeItem(at: exportDir)
        emit(.phase(.succeeded(tags: tags)))
    }

    /// Dial `buildkit:8088` and probe `Info`. If unreachable, start the builder
    /// (shell-out; first run pulls the image) and retry until a 300 s deadline.
    private nonisolated func dialBuilder(
        emit: @escaping @Sendable (BuildEvent) -> Void
    ) async throws -> BuildRunner {
        let logger = Logger(label: "berth.build")
        let deadline = Date().addingTimeInterval(300)
        var startedBuilder = false
        while true {
            try Task.checkCancellation()
            do {
                let fh = try await makeClient().dial(id: Self.builderID, port: Self.builderVsockPort)
                let runner = try BuildRunner(socket: fh, logger: logger)
                do {
                    try await runner.info()
                    return runner
                } catch {
                    await runner.shutdown()  // don't leak the ELG on a failed probe
                    throw error
                }
            } catch {
                try Task.checkCancellation()
                guard Date() < deadline else { throw error }
                if !startedBuilder {
                    emit(.phase(.preparingBuilder("Starting builder…")))
                }
                startedBuilder = true
                // Blocks until the builder VM is bootstrapped (first run pulls the image).
                _ = try await SystemControl.container(["builder", "start"])
                try await Task.sleep(for: .seconds(2))
            }
        }
    }

    private nonisolated func importBuiltImage(
        outTar: URL,
        tags: [String],
        emit: @escaping @Sendable (BuildEvent) -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: outTar.path) else {
            throw BuildFailure.noOutput
        }
        emit(.phase(.importing("Loading image")))
        let result = try await ClientImage.load(from: outTar.path, force: false)
        guard result.rejectedMembers.isEmpty else {
            throw BuildFailure.rejectedArchive(result.rejectedMembers)
        }
        for image in result.images {
            emit(.phase(.importing("Unpacking")))
            try await image.unpack(platform: nil, progressUpdate: nil)
            for tag in tags {
                emit(.phase(.importing("Tagging \(tag)")))
                _ = try await image.tag(new: tag)
            }
        }
    }
}
