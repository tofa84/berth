//
//  SystemControl.swift
//  berth
//
//  Engine lifecycle via the `container` CLI (shell-out). Lives outside the
//  XPC client because starting the apiserver registers a launchd agent, and
//  the install path is unreliable from inside a .app bundle — so we locate
//  the installed binary on known paths. Expanded in Phase 6 (System screen).
//

import Foundation

enum SystemControl {
    /// Known install locations for the `container` CLI, plus PATH lookup.
    static func locateBinary() -> String? {
        let candidates = ["/usr/local/bin/container", "/opt/homebrew/bin/container"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to `which` against a login-ish PATH.
        if let viaWhich = try? run("/usr/bin/which", ["container"]).trimmingCharacters(in: .whitespacesAndNewlines),
           !viaWhich.isEmpty, FileManager.default.isExecutableFile(atPath: viaWhich) {
            return viaWhich
        }
        return nil
    }

    @discardableResult
    static func system(_ subcommand: String) async throws -> String {
        guard let bin = locateBinary() else {
            throw SystemControlError.binaryNotFound
        }
        return try await Task.detached(priority: .userInitiated) {
            try run(bin, ["system", subcommand])
        }.value
    }

    /// Run the `container` CLI with arbitrary arguments (used by the Run modal,
    /// which mirrors the engine's own `container run` semantics).
    @discardableResult
    static func container(_ args: [String]) async throws -> String {
        guard let bin = locateBinary() else { throw SystemControlError.binaryNotFound }
        return try await Task.detached(priority: .userInitiated) {
            try run(bin, args)
        }.value
    }

    static func start() async throws { try await system("start") }
    static func stop() async throws { try await system("stop") }
    static func restart() async throws {
        try? await system("stop")
        try await system("start")
    }

    // MARK: - Process helper

    private static func run(_ launchPath: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()

        // Drain stdout and stderr concurrently. Reading one to EOF before the
        // other deadlocks if the child fills the still-unread pipe's buffer
        // (~16–64 KB on macOS) — easy to hit with a verbose `container run`
        // failure that spews to stderr while we block on stdout.
        let outFD = out.fileHandleForReading.fileDescriptor
        let errFD = err.fileHandleForReading.fileDescriptor
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "de.tomasetti.berth.proc-drain", attributes: .concurrent)
        queue.async(group: group) {
            outBox.value = FileHandle(fileDescriptor: outFD, closeOnDealloc: false).readDataToEndOfFile()
        }
        queue.async(group: group) {
            errBox.value = FileHandle(fileDescriptor: errFD, closeOnDealloc: false).readDataToEndOfFile()
        }
        group.wait()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let msg = String(data: errBox.value, encoding: .utf8) ?? "exit \(proc.terminationStatus)"
            throw SystemControlError.commandFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(data: outBox.value, encoding: .utf8) ?? ""
    }

    /// Collects one pipe's bytes off-thread. Each box is written by exactly one
    /// drain task and read only after `group.wait()`, so access is ordered.
    private final class DataBox: @unchecked Sendable {
        var value = Data()
    }
}

enum SystemControlError: LocalizedError {
    case binaryNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Couldn’t find the `container` command. Install it from github.com/apple/container."
        case .commandFailed(let msg):
            return msg
        }
    }
}
