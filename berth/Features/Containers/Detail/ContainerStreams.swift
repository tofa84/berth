//
//  ContainerStreams.swift
//  berth
//
//  Owns the per-container live streams for the detail view: log following and
//  stats polling. MainActor + @Observable so the views update as data arrives.
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class ContainerStreams {
    struct LogEntry: Identifiable {
        let id: Int
        let text: String
        let kind: LogKind
    }

    // Logs
    private(set) var logs: [LogEntry] = []
    var follow = true
    private var logTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var pending: [LogEntry] = []
    private var logSeq = 0
    private let logCap = 500

    // Stats
    private(set) var latest: ContainerStats?
    private(set) var cpuHistory: [Double] = []   // normalized 0...1 per sample
    private(set) var cpuPercentDisplay: Double = 0
    private var statsTask: Task<Void, Never>?
    private var sampler = CPUSampler()
    private var cores: Double = 1

    init() {}

    // MARK: Logs

    func startLogs(id: String, service: any ContainerServicing) {
        guard logTask == nil else { return }
        logs.removeAll()
        pending.removeAll()
        logSeq = 0
        logTask = Task { [weak self] in
            for await line in service.logStream(id: id) {
                if Task.isCancelled { break }
                self?.enqueue(line)
            }
        }
        // Coalesce bursts: incoming lines accumulate in `pending` and are published
        // to the observed `logs` array on a fixed cadence. Appending per line would
        // mutate `logs` many times within a single frame, making the detail view's
        // `onChange(of: logs.count)` auto-scroll fire — and re-enter ScrollView
        // layout — repeatedly per frame (the "update multiple times per frame" and
        // "layoutSubtreeIfNeeded ... already being laid out" warnings).
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.flush()
            }
        }
    }

    func stopLogs() {
        logTask?.cancel(); logTask = nil
        flushTask?.cancel(); flushTask = nil
        flush()
    }

    private func enqueue(_ line: LogLine) {
        logSeq += 1
        pending.append(LogEntry(id: logSeq, text: line.text, kind: line.kind))
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        logs.append(contentsOf: pending)
        pending.removeAll(keepingCapacity: true)
        if logs.count > logCap { logs.removeFirst(logs.count - logCap) }
    }

    // MARK: Stats

    func startStats(id: String, service: any ContainerServicing, cores: Int) {
        guard statsTask == nil else { return }
        self.cores = Double(max(1, cores))
        cpuHistory.removeAll()
        sampler = CPUSampler()
        cpuPercentDisplay = 0
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                if let s = try? await service.stats(id: id) { self?.ingest(s) }
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    func stopStats() { statsTask?.cancel(); statsTask = nil }

    private func ingest(_ s: ContainerStats) {
        latest = s
        guard let cpu = s.cpuUsageUsec,
              let percent = sampler.sample(usec: cpu, at: Date()) else { return }
        cpuPercentDisplay = percent
        cpuHistory.append(min(1, (percent / 100) / cores))
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
    }

    // MARK: Lifecycle

    func stopAll() { stopLogs(); stopStats() }

    var coresForDisplay: Double { cores }

    var memoryFraction: Double {
        guard let used = latest?.memoryUsageBytes, let limit = latest?.memoryLimitBytes, limit > 0 else { return 0 }
        return Double(used) / Double(limit)
    }
}
