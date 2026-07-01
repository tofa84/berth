//
//  FormattersTests.swift
//  berthTests
//
//  `Format.*` are pure. `uptime`/`relative` take an injectable `now` for
//  determinism; `bytes`/`relative` delegate to locale-dependent system
//  formatters, so those are asserted on structure (not exact strings).
//

import Testing
import Foundation
@testable import berth

struct FormattersTests {

    @Test func percent() {
        #expect(Format.percent(0.0) == "0%")
        #expect(Format.percent(0.5) == "50%")
        #expect(Format.percent(0.996) == "100%")   // rounds up
        #expect(Format.percent(1.0) == "100%")
    }

    @Test func uptimeNil() {
        #expect(Format.uptime(since: nil) == "—")
    }

    @Test func uptimeBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(Format.uptime(since: now.addingTimeInterval(-30), now: now) == "just now")
        #expect(Format.uptime(since: now.addingTimeInterval(30), now: now) == "just now")   // future → clamps
        #expect(Format.uptime(since: now.addingTimeInterval(-90), now: now) == "1m")
        #expect(Format.uptime(since: now.addingTimeInterval(-(2 * 3600 + 5 * 60)), now: now) == "2h 5m")
        #expect(Format.uptime(since: now.addingTimeInterval(-(3 * 86400 + 2 * 3600)), now: now) == "3d 2h")
    }

    @Test func bytes() {
        #expect(Format.bytes(nil) == "—")
        // Non-nil delegates to ByteCountFormatter (locale-dependent): assert it
        // produced a real, non-dash string.
        let s = Format.bytes(UInt64(5 * 1024 * 1024))
        #expect(s != "—")
        #expect(!s.isEmpty)
    }

    @Test func relativeEpochSentinelAndNil() {
        // The Unix-epoch fallback (<= 86_400s since 1970) is treated as unknown.
        #expect(Format.relative(nil) == "—")
        #expect(Format.relative(Date(timeIntervalSince1970: 0)) == "—")
        #expect(Format.relative(Date(timeIntervalSince1970: 86_400)) == "—")   // guard is strict `>`
        // A genuine recent date renders something other than the dash.
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(Format.relative(now.addingTimeInterval(-3600), now: now) != "—")
    }
}
