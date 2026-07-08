//
//  EngineConnection.swift
//  berth
//
//  Tracks whether the apple/container engine (apiserver) is reachable, by
//  polling ClientHealthCheck.ping(). Drives the global "not running" state,
//  the sidebar status card, and a version handshake against the pinned engine.
//

import Foundation
import Observation
import ContainerAPIClient
import ContainerResource

@MainActor
@Observable
final class EngineConnection {
    enum State: Sendable {
        case connecting
        case running(SystemHealth)
        case down(String)
    }

    /// The engine version this app was built against (SPM pin).
    static let pinnedVersion = "1.1.0"

    private(set) var state: State = .connecting
    private(set) var starting = false

    /// Bumped every time the engine becomes reachable after not being reachable
    /// (first connect, or recovery after a stop/restart). Screens key their load
    /// on this (`.task(id: engine.epoch)`) so they refresh once the engine — and
    /// its XPC connection — is back, instead of staying stuck on a load error.
    private(set) var epoch = 0

    private let service: any ContainerServicing
    private var pollTask: Task<Void, Never>?

    init(service: any ContainerServicing) {
        self.service = service
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var health: SystemHealth? {
        if case .running(let h) = state { return h }
        return nil
    }

    /// Engine semantic version parsed out of the verbose apiServerVersion string,
    /// e.g. "container-apiserver version 1.0.0 (build: release, …)" -> "1.0.0".
    var version: String? {
        guard let raw = health?.apiServerVersion else { return nil }
        return Self.parseVersion(from: raw)
    }

    /// Extracts a semantic `N.N.N` version from the verbose apiServerVersion
    /// string; falls back to the raw string when no such pattern is present.
    nonisolated static func parseVersion(from raw: String) -> String {
        if let m = raw.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
            return String(raw[m])
        }
        return raw
    }

    var versionMismatch: Bool {
        guard let v = version else { return false }
        return v != Self.pinnedVersion
    }

    func startMonitoring() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval: Duration = (self?.isRunning ?? false) ? .seconds(5) : .seconds(2)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        do {
            let health = try await service.health()
            let wasRunning = isRunning
            state = .running(health)
            if !wasRunning { epoch += 1 }   // not-running -> running: trigger a reload
        } catch {
            // While an explicit start is in flight, the apiserver throws transient
            // errors on every poll until its Mach service binds. Keep the prior
            // state (the "Starting…" affordance) instead of flickering each error;
            // a genuine failure surfaces once `starting` clears.
            if !starting { state = .down(Format.error(error)) }
        }
    }

    /// Attempt to start the engine via the CLI, then re-check.
    func startEngine() async {
        starting = true
        defer { starting = false }
        do {
            try await SystemControl.start()
        } catch {
            state = .down(Format.error(error))
            return
        }
        // `container system start` returns once launchd has bootstrapped the job,
        // but the apiserver's Mach service needs a moment more before it accepts
        // connections. Poll until it's reachable (keeping the "Starting…" state)
        // rather than flashing "not running" on the first, usually-failing ping.
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        repeat {
            await refresh()
            if isRunning { return }
            try? await Task.sleep(for: .milliseconds(400))
        } while ContinuousClock.now < deadline
    }
}
