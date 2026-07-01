//
//  CPUSamplerTests.swift
//  berthTests
//
//  Pure delta math: cumulative CPU-time counter (µs) → percent of one core.
//  All values chosen to be exact in binary floating point.
//

import Testing
import Foundation
@testable import berth

struct CPUSamplerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func firstSampleHasNoBaseline() {
        var s = CPUSampler()
        #expect(s.sample(usec: 1_000_000, at: t0) == nil)
    }

    @Test func steadyLoadYieldsPercentOfOneCore() {
        var s = CPUSampler()
        _ = s.sample(usec: 0, at: t0)
        // 0.5s of CPU time over 1s of wall time = 50% of one core.
        #expect(s.sample(usec: 500_000, at: t0.addingTimeInterval(1)) == 50.0)
        // Two full cores for the next second: +2_000_000µs → 200%.
        #expect(s.sample(usec: 2_500_000, at: t0.addingTimeInterval(2)) == 200.0)
    }

    @Test func counterResetClampsToZero() {
        var s = CPUSampler()
        _ = s.sample(usec: 900, at: t0)
        // The counter went backwards (container restarted): report 0, not negative.
        #expect(s.sample(usec: 100, at: t0.addingTimeInterval(1)) == 0)
        // The reset value became the new baseline.
        #expect(s.sample(usec: 1_000_100, at: t0.addingTimeInterval(2)) == 100.0)
    }

    @Test func zeroWallIntervalIsSkipped() {
        var s = CPUSampler()
        _ = s.sample(usec: 100, at: t0)
        #expect(s.sample(usec: 200, at: t0) == nil)
    }
}
