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
    private var logSeq = 0
    private let logCap = 500

    // Stats
    private(set) var latest: ContainerStats?
    private(set) var cpuHistory: [Double] = []   // normalized 0...1 per sample
    private(set) var cpuPercentDisplay: Double = 0
    private var statsTask: Task<Void, Never>?
    private var prevCPU: (usec: UInt64, at: Date)?
    private var cores: Double = 1

    init() {}

    // MARK: Logs

    func startLogs(id: String, service: ContainerService) {
        guard logTask == nil else { return }
        logs.removeAll()
        logSeq = 0
        logTask = Task { [weak self] in
            for await line in service.logStream(id: id) {
                if Task.isCancelled { break }
                self?.append(line)
            }
        }
    }

    func stopLogs() { logTask?.cancel(); logTask = nil }

    private func append(_ line: LogLine) {
        logSeq += 1
        logs.append(LogEntry(id: logSeq, text: line.text, kind: line.kind))
        if logs.count > logCap { logs.removeFirst(logs.count - logCap) }
    }

    // MARK: Stats

    func startStats(id: String, service: ContainerService, cores: Int) {
        guard statsTask == nil else { return }
        self.cores = Double(max(1, cores))
        cpuHistory.removeAll()
        prevCPU = nil
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
        guard let cpu = s.cpuUsageUsec else { return }
        let now = Date()
        if let prev = prevCPU {
            let dCpu = Double(cpu >= prev.usec ? cpu - prev.usec : 0)        // µs of CPU time
            let dWall = now.timeIntervalSince(prev.at) * 1_000_000           // µs of wall time
            if dWall > 0 {
                let perCore = dCpu / dWall                                   // fraction of one core
                cpuPercentDisplay = perCore * 100
                cpuHistory.append(min(1, perCore / cores))
                if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
            }
        }
        prevCPU = (cpu, now)
    }

    // MARK: Lifecycle

    func stopAll() { stopLogs(); stopStats() }

    var coresForDisplay: Double { cores }

    var memoryFraction: Double {
        guard let used = latest?.memoryUsageBytes, let limit = latest?.memoryLimitBytes, limit > 0 else { return 0 }
        return Double(used) / Double(limit)
    }
}
