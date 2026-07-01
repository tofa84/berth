//
//  CPUSampler.swift
//  berth
//
//  Converts the engine's cumulative CPU-time counter (µs of CPU time used)
//  into a utilization percentage between two readings. One sampler per
//  sampled container; shared by the Dashboard aggregate and the detail
//  Stats tab so the delta math lives (and is tested) in one place.
//

import Foundation

nonisolated struct CPUSampler {
    private var prev: (usec: UInt64, at: Date)?

    /// Percent of one core used since the previous reading (100 == one full
    /// core; multi-core containers can exceed 100). Returns nil when there is
    /// no baseline yet or no wall time has passed; a counter reset (new value
    /// below the baseline) clamps to 0 instead of going negative.
    mutating func sample(usec: UInt64, at now: Date) -> Double? {
        defer { prev = (usec, now) }
        guard let prev else { return nil }
        let dCpu = Double(usec >= prev.usec ? usec - prev.usec : 0)   // µs of CPU time
        let dWall = now.timeIntervalSince(prev.at) * 1_000_000        // µs of wall time
        guard dWall > 0 else { return nil }
        return (dCpu / dWall) * 100
    }
}
