//
//  LogFormatTests.swift
//  berthTests
//
//  `LogFormat.parse` is pure: raw line + stream tag in, presentation parts
//  out. Container output is arbitrary, so the suite pins both the recognized
//  shapes and the conservative fallbacks.
//

import Testing
@testable import berth

struct LogFormatTests {

    @Test func vminitdStyleLine() {
        let p = LogFormat.parse("08:53:05.733 warning vminitd: memory threshold exceeded (83,5 / 83,9 MB)", kind: .stdout)
        #expect(p.timestamp == "08:53:05.733")
        #expect(p.level == "warning")
        #expect(p.severity == .warning)
        #expect(p.message == "vminitd: memory threshold exceeded (83,5 / 83,9 MB)")
    }

    @Test func infoAfterClockTimestamp() {
        let p = LogFormat.parse("08:53:05.726 info vminitd: created vmexec init process", kind: .stdout)
        #expect(p.timestamp == "08:53:05.726")
        #expect(p.level == "info")
        #expect(p.severity == .info)
        #expect(p.message == "vminitd: created vmexec init process")
    }

    @Test func isoTimestamp() {
        let p = LogFormat.parse("2026-07-01T08:53:05.726Z ERROR db: connection refused", kind: .stdout)
        #expect(p.timestamp == "2026-07-01T08:53:05.726Z")
        #expect(p.level == "error")
        #expect(p.severity == .error)
        #expect(p.message == "db: connection refused")
    }

    @Test func bracketedLevelWithoutTimestamp() {
        let p = LogFormat.parse("[WARN] disk nearly full", kind: .stdout)
        #expect(p.timestamp == nil)
        #expect(p.level == "warn")
        #expect(p.severity == .warning)
        #expect(p.message == "disk nearly full")
    }

    @Test func colonSuffixedLevel() {
        let p = LogFormat.parse("error: something broke", kind: .stdout)
        #expect(p.level == "error")
        #expect(p.severity == .error)
        #expect(p.message == "something broke")
    }

    @Test func allCapsLevelWithoutMarkers() {
        let p = LogFormat.parse("ERROR failed to bind port", kind: .stdout)
        #expect(p.level == "error")
        #expect(p.severity == .error)
    }

    @Test func lowercaseProseStaysPlain() {
        // "info" as an ordinary sentence-leading word — no timestamp, no
        // bracket/colon/CAPS marker — must not become a level column.
        let p = LogFormat.parse("info about the run follows", kind: .stdout)
        #expect(p.timestamp == nil)
        #expect(p.level == nil)
        #expect(p.severity == .neutral)
        #expect(p.message == "info about the run follows")
    }

    @Test func stderrFallbackStaysError() {
        let p = LogFormat.parse("panic: runtime error", kind: .stderr)
        #expect(p.severity == .error)
        // And a completely plain stderr line keeps the red fallback too.
        let plain = LogFormat.parse("something went wrong", kind: .stderr)
        #expect(plain.level == nil)
        #expect(plain.severity == .error)
    }

    @Test func parsedLevelOverridesStream() {
        // A structured line on stderr keeps its own (milder) severity.
        let p = LogFormat.parse("08:53:05.726 info shutting down gracefully", kind: .stderr)
        #expect(p.severity == .info)
        #expect(p.level == "info")
    }

    @Test func timestampWithoutLevel() {
        let p = LogFormat.parse("08:53:05.726 GET /healthz 200", kind: .stdout)
        #expect(p.timestamp == "08:53:05.726")
        #expect(p.level == nil)
        #expect(p.severity == .neutral)
        #expect(p.message == "GET /healthz 200")
    }

    @Test func levelWithEmptyMessageStaysPlain() {
        let p = LogFormat.parse("WARNING", kind: .stdout)
        #expect(p.level == nil)
        #expect(p.severity == .neutral)
        #expect(p.message == "WARNING")
    }

    @Test func sentinel() {
        let p = LogFormat.parse(LogLine.stoppedSentinel, kind: .stdout)
        #expect(p.severity == .sentinel)
        #expect(p.message == LogLine.stoppedSentinel)
        #expect(p.timestamp == nil)
        #expect(p.level == nil)
    }

    @Test func emptyLine() {
        let p = LogFormat.parse("", kind: .stdout)
        #expect(p.severity == .neutral)
        #expect(p.message == "")
        #expect(p.timestamp == nil)
    }
}
