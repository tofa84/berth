//
//  BuildFormModel.swift
//  berth
//
//  Builds the `container build …` argument vector — shown as the command
//  preview and mapped 1:1 into a `BuildRequest`. Execution is native gRPC (not
//  a shell-out), but the preview mirrors the equivalent CLI command, matching
//  the Run sheet's convention. FS probes are injected so validation is
//  hermetically testable (Layer A).
//

import Foundation
import Observation

@MainActor
@Observable
final class BuildFormModel {
    var contextDir = ""
    /// Empty → `<contextDir>/Dockerfile`.
    var dockerfileOverride = ""
    var tag = ""
    var buildArgs: [KeyValueField] = []
    var labels: [KeyValueField] = []
    var target = ""
    var platformARM64 = true
    var platformAMD64 = false
    var noCache = false
    var pull = false

    var busy = false

    @ObservationIgnored private let fileExists: (String) -> Bool
    @ObservationIgnored private let fileSize: (String) -> Int?

    init(
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        fileSize: @escaping (String) -> Int? = { (try? FileManager.default.attributesOfItem(atPath: $0)[.size]) as? Int }
    ) {
        self.fileExists = fileExists
        self.fileSize = fileSize
    }

    var dockerfilePath: String {
        let override = dockerfileOverride.trimmingCharacters(in: .whitespaces)
        if !override.isEmpty { return override }
        let ctx = contextDir.trimmingCharacters(in: .whitespaces)
        return ctx.isEmpty ? "" : (ctx as NSString).appendingPathComponent("Dockerfile")
    }

    var platforms: [String] {
        var p: [String] = []
        if platformARM64 { p.append("linux/arm64") }
        if platformAMD64 { p.append("linux/amd64") }
        return p
    }

    /// First failing precondition, or nil when the form is ready to build.
    var validationError: String? {
        let ctx = contextDir.trimmingCharacters(in: .whitespaces)
        if ctx.isEmpty { return "Choose a build context folder." }
        if !fileExists(ctx) { return "Context folder does not exist." }
        let dockerfile = dockerfilePath
        if !fileExists(dockerfile) { return "Dockerfile not found at \(dockerfile)." }
        if let size = fileSize(dockerfile), size >= BuildRequest.maxDockerfileBytes {
            return "Dockerfile is too large (≥ \(BuildRequest.maxDockerfileBytes) bytes)."
        }
        if tag.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter an image tag." }
        if platforms.isEmpty { return "Select at least one platform." }
        return nil
    }

    var canBuild: Bool { validationError == nil && !busy }

    /// Argument vector, mirroring the equivalent `container build` command.
    var argv: [String] {
        var a = ["build"]
        let t = tag.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { a += ["-t", t] }
        for arg in buildArgs where !arg.key.isEmpty {
            a += ["--build-arg", "\(arg.key)=\(arg.value)"]
        }
        for label in labels where !label.key.isEmpty {
            a += ["--label", "\(label.key)=\(label.value)"]
        }
        if !target.trimmingCharacters(in: .whitespaces).isEmpty { a += ["--target", target] }
        for platform in platforms { a += ["--platform", platform] }
        if noCache { a.append("--no-cache") }
        if pull { a.append("--pull") }
        let override = dockerfileOverride.trimmingCharacters(in: .whitespaces)
        if !override.isEmpty { a += ["-f", override] }
        a.append(contextDir.trimmingCharacters(in: .whitespaces))  // context is last
        return a
    }

    var commandPreview: String { CommandPreview.container(argv) }

    func request() -> BuildRequest {
        BuildRequest(
            contextDir: contextDir.trimmingCharacters(in: .whitespaces),
            dockerfilePath: dockerfilePath,
            tags: [tag.trimmingCharacters(in: .whitespaces)],
            buildArgs: buildArgs.filter { !$0.key.isEmpty }.map { "\($0.key)=\($0.value)" },
            labels: labels.filter { !$0.key.isEmpty }.map { "\($0.key)=\($0.value)" },
            target: target.trimmingCharacters(in: .whitespaces),
            platforms: platforms,
            noCache: noCache,
            pull: pull)
    }

    func addArg() { buildArgs.append(KeyValueField()) }
    func addLabel() { labels.append(KeyValueField()) }

    /// Pre-fill the form from a prior request (re-run).
    func fill(from request: BuildRequest) {
        contextDir = request.contextDir
        let defaultDockerfile = (request.contextDir as NSString).appendingPathComponent("Dockerfile")
        dockerfileOverride = request.dockerfilePath == defaultDockerfile ? "" : request.dockerfilePath
        tag = request.tags.first ?? ""
        buildArgs = request.buildArgs.map(KeyValueField.init(entry:))
        labels = request.labels.map(KeyValueField.init(entry:))
        target = request.target
        platformARM64 = request.platforms.contains("linux/arm64")
        platformAMD64 = request.platforms.contains("linux/amd64")
        noCache = request.noCache
        pull = request.pull
    }
}
