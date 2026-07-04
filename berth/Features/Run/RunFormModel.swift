//
//  RunFormModel.swift
//  berth
//
//  Builds and executes a `container run` command. Containers are always started
//  detached from the GUI (output is viewable in the container's Logs tab); the
//  preview reflects the chosen flags.
//

import Foundation
import Observation

@MainActor
@Observable
final class RunFormModel {
    struct PortMap: Identifiable { let id = UUID(); var host = ""; var container = ""; var udp = false }

    var image = ""
    var name = ""
    var arch = "arm64"
    var env: [KeyValueField] = []
    var ports: [PortMap] = []
    var cpus = 2
    var memoryGB = 1
    var remove = false
    var readOnly = false
    var rosetta = false

    var busy = false
    var error: String?

    var canRun: Bool { !image.trimmingCharacters(in: .whitespaces).isEmpty && !busy }

    /// Argument vector exactly as previewed — and exactly as executed. The GUI
    /// always runs detached (output is viewed in the container's Logs tab; an
    /// attached `-i`/`-t` session has nowhere to go), so `-d` is unconditional.
    var argv: [String] {
        var a = ["run", "-d"]
        if remove { a.append("--rm") }
        if readOnly { a.append("--read-only") }
        if rosetta { a.append("--rosetta") }
        if !name.isEmpty { a += ["--name", name] }
        if !arch.isEmpty { a += ["--arch", arch] }
        a += ["-c", "\(cpus)", "-m", "\(memoryGB)G"]
        for e in env where !e.key.isEmpty {
            a += ["-e", "\(e.key)=\(e.value)"]
        }
        for p in ports where !p.host.isEmpty && !p.container.isEmpty {
            a += ["-p", "\(p.host):\(p.container)" + (p.udp ? "/udp" : "")]
        }
        if !image.isEmpty { a.append(image) }
        return a
    }

    var commandPreview: String { CommandPreview.container(argv) }

    /// Execute. Always detached so the GUI never blocks. Returns true on success.
    func run() async -> Bool {
        error = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await SystemControl.container(argv)
            return true
        } catch {
            self.error = Format.error(error)
            return false
        }
    }

    func addEnv() { env.append(KeyValueField()) }
    func addPort() { ports.append(PortMap()) }
}
