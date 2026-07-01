//
//  DashboardStore.swift
//  berth
//
//  Live overview: counts, disk usage, and aggregate CPU/memory sampled across
//  running containers (the engine doesn't expose VM host metrics or history,
//  so we self-sample on a timer while the screen is visible).
//

import Foundation
import Observation
import ContainerResource

@MainActor
@Observable
final class DashboardStore {
    var loaded = false
    var lastRefresh = Date()

    // Counts / sizes
    var running = 0
    var total = 0
    var imageCount = 0
    var imageSize: UInt64 = 0
    var reclaimable: UInt64 = 0
    var volumeCount = 0
    var volumeSize: UInt64 = 0

    // Aggregate load
    var cpuPercent = 0.0          // summed across running containers
    var memUsed: UInt64 = 0
    var memLimit: UInt64 = 0
    var cpuHistory: [Double] = [] // normalized 0...1 (by total allocated cores)
    private(set) var totalCores = 1

    // Per-container live stats for the running list
    var perStats: [String: (cpu: Double, mem: UInt64)] = [:]
    var runningContainers: [ContainerSnapshot] = []

    private unowned let app: AppModel
    private let service: any ContainerServicing
    private var liveTask: Task<Void, Never>?
    private var samplers: [String: CPUSampler] = [:]

    init(service: any ContainerServicing, app: AppModel) {
        self.service = service
        self.app = app
    }

    var memFraction: Double { memLimit > 0 ? Double(memUsed) / Double(memLimit) : 0 }
    var cpuFraction: Double { min(1, (cpuPercent / 100) / Double(totalCores)) }

    func start() {
        guard liveTask == nil else { return }
        liveTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.refreshContainers()
                if tick % 5 == 0 { await self?.refreshResources() }
                self?.lastRefresh = Date()
                tick += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() { liveTask?.cancel(); liveTask = nil }

    func refreshContainers() async {
        guard let list = try? await app.containersFeed.refresh() else { return }
        total = list.count
        let runs = list.filter { $0.status == .running }
        running = runs.count
        runningContainers = runs
        totalCores = max(1, runs.reduce(0) { $0 + $1.allocatedCPUs })

        // Drop CPU baselines for containers that have exited/been deleted, so the
        // sampling map stays bounded by the current running set.
        let liveIDs = Set(runs.map { $0.id })
        samplers = samplers.filter { liveIDs.contains($0.key) }

        // Memory limit is a static config value, so sum it from the snapshots
        // unconditionally — a transient stats() failure shouldn't make the total
        // allocated-memory caption jump down and back up.
        let limitSum = runs.reduce(UInt64(0)) { $0 + $1.memoryLimitBytes }

        // Fetch all stats concurrently: one serial XPC round-trip per running
        // container would make the refresh O(n) in latency and could overrun
        // the 2s tick on container-heavy setups.
        let service = self.service
        let statsByID = await withTaskGroup(of: (String, ContainerStats?).self) { group in
            for c in runs {
                let id = c.id
                group.addTask { (id, try? await service.stats(id: id)) }
            }
            var out: [String: ContainerStats] = [:]
            for await (id, stats) in group {
                if let stats { out[id] = stats }
            }
            return out
        }

        var aggCpu = 0.0, usedSum: UInt64 = 0
        var per: [String: (cpu: Double, mem: UInt64)] = [:]
        let now = Date()
        for c in runs {
            guard let s = statsByID[c.id] else { continue }
            let mem = s.memoryUsageBytes ?? 0
            usedSum += mem
            var cpuPct = 0.0
            if let cpu = s.cpuUsageUsec {
                cpuPct = samplers[c.id, default: CPUSampler()].sample(usec: cpu, at: now) ?? 0
            }
            aggCpu += cpuPct
            per[c.id] = (cpuPct, mem)
        }
        perStats = per
        cpuPercent = aggCpu
        memUsed = usedSum
        memLimit = limitSum
        cpuHistory.append(cpuFraction)
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
        loaded = true
    }

    func refreshResources() async {
        let active = Set(runningContainers.map { $0.configuration.image.reference })
        if let img = try? await service.imageSummary(active: active) {
            imageCount = img.count
            imageSize = img.totalSize
            reclaimable = img.reclaimable
            app.counts[.images] = img.count
        }
        if let vol = try? await service.volumeSummary() {
            volumeCount = vol.count
            volumeSize = vol.totalSize
            app.counts[.volumes] = vol.count
        }
    }
}
