//
//  ResourceStore.swift
//  berth
//
//  Shared behavior for the per-screen list stores (containers, images,
//  volumes, networks, registries): LoadState bookkeeping, the global search
//  filter, and the run/prune action brackets with their toast error surface.
//

import Foundation

@MainActor
protocol ResourceStore: AnyObject {
    associatedtype Resource: Sendable
    /// The listed resources, as last loaded.
    var state: LoadState<[Resource]> { get set }
    /// One-line failure surface for the most recent action (error toast).
    var actionError: String? { get set }
    /// In-flight flag for whole-list operations; row-level work is per-store.
    var busy: Bool { get set }
    /// Fetch the list (and any derived maps) from the engine.
    func load() async
    /// Whether `resource` matches an already-normalized search term.
    func matches(_ resource: Resource, term: String) -> Bool
}

extension ResourceStore {
    var all: [Resource] { state.value ?? [] }

    /// Flip `.idle` to `.loading` at the start of `load()`: the first load shows
    /// a spinner, later reloads keep the stale list visible instead of flashing.
    func beginLoading() {
        if case .idle = state { state = .loading }
    }

    /// `base` narrowed by the global search query — trimmed, case-insensitive;
    /// an empty query passes everything through.
    func searchFiltered(_ query: String, in base: [Resource]) -> [Resource] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return base }
        return base.filter { matches($0, term: term) }
    }

    /// One mutating engine action: clears the previous error, holds `busy`,
    /// reloads on success, and lands failures in `actionError`.
    @discardableResult
    func runAction(_ work: () async throws -> Void) async -> Bool {
        actionError = nil
        busy = true
        defer { busy = false }
        do {
            try await work()
            await load()
            return true
        } catch {
            actionError = Format.error(error)
            return false
        }
    }

    /// Best-effort bulk deletion (prune): every operation is attempted, failures
    /// are collected into one aggregate toast, then the list reloads.
    func runPrune(noun: String, _ operations: [(label: String, run: () async throws -> Void)]) async {
        actionError = nil
        busy = true
        defer { busy = false }
        var failures: [String] = []
        for operation in operations {
            do { try await operation.run() }
            catch { failures.append("\(operation.label): \(Format.error(error))") }
        }
        actionError = pruneSummary(failures, of: operations.count, noun: noun)
        await load()
    }
}
