//
//  FormattersTests.swift
//  berthTests
//
//  `Format.*` are pure. `uptime`/`relative` take an injectable `now` for
//  determinism; `bytes`/`percent` take an injectable `locale` so exact
//  strings can be pinned per locale (the current-locale defaults are only
//  asserted structurally).
//

import Testing
import Foundation
@testable import berth

struct FormattersTests {
    private let en = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    @Test func percentFraction() {
        #expect(Format.percent(0.0, locale: en) == "0%")
        #expect(Format.percent(0.5, locale: en) == "50%")
        #expect(Format.percent(0.996, locale: en) == "100%")   // rounds up
        #expect(Format.percent(1.0, locale: en) == "100%")
        // German separates the unit — with a narrow no-break space.
        #expect(Format.percent(0.5, locale: de) == "50\u{202F}%")
    }

    @Test func percentPoints() {
        #expect(Format.percent(points: 0.8, locale: en) == "0.8%")
        #expect(Format.percent(points: 1.0, locale: en) == "1.0%")
        #expect(Format.percent(points: 0.8, locale: de) == "0,8\u{202F}%")
        #expect(Format.percent(points: 0, locale: de) == "0,0\u{202F}%")
        // Aggregate CPU may exceed 100 points (summed across containers).
        #expect(Format.percent(points: 450, digits: 0, locale: en) == "450%")
    }

    @Test func narrowUnitSpace() {
        #expect(Format.narrowUnitSpace("5.2 MB") == "5.2\u{202F}MB")
        #expect(Format.narrowUnitSpace("50\u{00A0}%") == "50\u{202F}%")
        // Only the last space is touched; earlier ones survive.
        #expect(Format.narrowUnitSpace("1 234 MB") == "1 234\u{202F}MB")
        // Idempotent, and a no-op without any space.
        #expect(Format.narrowUnitSpace("5.2\u{202F}MB") == "5.2\u{202F}MB")
        #expect(Format.narrowUnitSpace("100%") == "100%")
        #expect(Format.narrowUnitSpace("") == "")
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

    @Test func bytesLocalized() {
        #expect(Format.bytes(nil) == "—")
        #expect(Format.bytes(Int64(5_200_000), locale: en) == "5.2\u{202F}MB")
        #expect(Format.bytes(Int64(5_200_000), locale: de) == "5,2\u{202F}MB")
        #expect(Format.bytes(UInt64(9_970_000_000), locale: de) == "9,97\u{202F}GB")
        // Current-locale default still produces a real, non-dash string.
        let s = Format.bytes(UInt64(5 * 1024 * 1024))
        #expect(s != "—")
        #expect(!s.isEmpty)
    }

    @Test func errorPrefersLocalizedDescription() {
        #expect(Format.error(SystemControlError.commandFailed("boom")) == "boom")
        struct Plain: Error {}
        #expect(Format.error(Plain()) == "Plain()")
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

    @Test func relativeFromISO8601() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Both RFC-3339 shapes parse: with and without fractional seconds.
        #expect(Format.relative(iso8601: "2023-11-13T22:13:20Z", now: now) != "—")
        #expect(Format.relative(iso8601: "2023-11-13T22:13:20.123Z", now: now) != "—")
        // Fractional and plain render of the same instant agree.
        #expect(Format.relative(iso8601: "2023-11-12T22:13:20Z", now: now)
            == Format.relative(iso8601: "2023-11-12T22:13:20.000Z", now: now))
        // Empty → dash; garbage passes through verbatim.
        #expect(Format.relative(iso8601: "", now: now) == "—")
        #expect(Format.relative(iso8601: "not a date", now: now) == "not a date")
    }

    @Test func prettyJSONIsSortedAndPretty() {
        struct Sample: Encodable {
            let b: Int
            let a: String
        }
        let json = Format.prettyJSON(Sample(b: 2, a: "x"))
        // Sorted keys ("a" before "b") and multi-line output.
        #expect(json.contains("\"a\" : \"x\""))
        #expect(json.range(of: "\"a\"")!.lowerBound < json.range(of: "\"b\"")!.lowerBound)
        #expect(json.contains("\n"))
    }
}
