//
//  BuildsStore.swift
//  berth
//
//  Owns the Builds screen state: the buildkit builder status (+ lifecycle
//  actions) and the currently-running build. Consumes the service's
//  `performBuild` event stream, folding progress lines into a structured step
//  list and a raw log, coalesced on a 100 ms cadence so a chatty build doesn't
//  relayout the log per line (the ContainerStreams lesson).
//

import Foundation
import Observation

@MainActor
@Observable
final class BuildsStore {
    // Builder status card.
    var builder: LoadState<BuilderInfo> = .idle
    var actionError: String?
    var busy = false

    // Active / last build.
    private(set) var phase: BuildPhase?
    private(set) var folder = BuildStepFolder()
    private(set) var rawLines: [String] = []
    private(set) var builderPull: PullProgress?
    private(set) var lastRequest: BuildRequest?
    var showRawLog = false

    // Local build history (newest first).
    private(set) var history: [BuildRecord] = []
    /// Injectable so tests point it at a temp dir instead of Application Support.
    @ObservationIgnored var historyFile = BuildHistoryFile.default

    private let service: any ContainerServicing
    private unowned let app: AppModel
    @ObservationIgnored private var pendingLines: [String] = []
    @ObservationIgnored private var buildTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var buildStartedAt: Date?
    private static let rawCap = 2000

    init(service: any ContainerServicing, app: AppModel) {
        self.service = service
        self.app = app
    }

    var isBuilding: Bool {
        guard let phase else { return false }
        return !phase.isTerminal
    }

    // MARK: Builder status + lifecycle

    func load() async {
        history = historyFile.load()
        do {
            builder = .loaded(try await service.builderInfo())
        } catch {
            builder = .failed(Format.error(error))
        }
    }

    func startBuilder() async { await runLifecycle { try await self.service.startBuilder() } }
    func stopBuilder() async { await runLifecycle { try await self.service.stopBuilder() } }
    func deleteBuilder() async { await runLifecycle { try await self.service.deleteBuilder(force: true) } }

    private func runLifecycle(_ work: () async throws -> Void) async {
        actionError = nil
        busy = true
        defer { busy = false }
        do {
            try await work()
            await load()
        } catch {
            actionError = Format.error(error)
        }
    }

    // MARK: Build

    func startBuild(_ request: BuildRequest) {
        guard !isBuilding else { return }
        lastRequest = request
        buildStartedAt = Date()
        phase = .preparingBuilder("Preparing…")
        folder = BuildStepFolder()
        rawLines = []
        pendingLines = []
        builderPull = nil
        showRawLog = false
        app.counts[.builds] = 1

        flushTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.flushPending()
            }
        }

        buildTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in self.service.performBuild(request) {
                switch event {
                case .line(let line): self.pendingLines.append(line)
                case .phase(let phase): self.phase = phase
                case .builderPull(let progress): self.builderPull = progress
                }
            }
            self.flushTask?.cancel()
            self.flushPending()
            await self.finishBuild()
        }
    }

    func cancelBuild() {
        buildTask?.cancel()
        // The stream ends; `finishBuild` normalizes a still-running phase to
        // Cancelled. Setting it here too keeps the UI responsive immediately.
        if isBuilding { phase = .failed(message: "Cancelled") }
    }

    private func flushPending() {
        guard !pendingLines.isEmpty else { return }
        for line in pendingLines {
            rawLines.append(line)
            folder.ingest(line)
        }
        if rawLines.count > Self.rawCap {
            rawLines.removeFirst(rawLines.count - Self.rawCap)
        }
        pendingLines.removeAll(keepingCapacity: true)
    }

    private func finishBuild() async {
        if let phase, !phase.isTerminal {
            self.phase = .failed(message: "Cancelled")
        }
        buildTask = nil
        flushTask = nil
        recordHistory()
        if case .succeeded = phase {
            await app.images.load()
        }
        // Clear the badge LAST so an observer waiting on it (tests, and the UI)
        // sees a fully-finished build — including the post-success images refresh.
        app.counts[.builds] = nil
    }

    /// Append the just-finished build to the local history and reload it.
    private func recordHistory() {
        guard let request = lastRequest, let phase else { return }
        let outcome: BuildRecord.Outcome
        switch phase {
        case .succeeded(let tags): outcome = .succeeded(tags: tags)
        case .failed(let message): outcome = message == "Cancelled" ? .cancelled : .failed(message: message)
        default: return  // non-terminal — shouldn't happen here
        }
        let record = BuildRecord(
            id: UUID(),
            date: Date(),
            request: request,
            outcome: outcome,
            duration: buildStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
        try? historyFile.append(record)
        history = historyFile.load()
    }

    /// Re-run a past build: hand its request to the sheet.
    func rerun(_ record: BuildRecord) {
        app.buildPrefill = record.request
    }
}
