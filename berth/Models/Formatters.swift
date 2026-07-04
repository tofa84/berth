//
//  Formatters.swift
//  berth
//
//  Pure formatting helpers (bytes, durations, dates). No engine access.
//
//  Numbers follow the user's locale (one decimal separator everywhere), and
//  values read as a single token: the space before a unit (GB / MB / %) is a
//  narrow no-break space. `locale` is injectable so tests can pin exact
//  strings per locale.
//

import Foundation

enum Format {
    /// Human byte size, e.g. "1.2 GB" (en) / "1,2 GB" (de).
    static func bytes(_ value: UInt64?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let value else { return "—" }
        return bytes(Int64(min(value, UInt64(Int64.max))), locale: locale)
    }

    static func bytes(_ value: Int64, locale: Locale = .autoupdatingCurrent) -> String {
        narrowUnitSpace(value.formatted(
            .byteCount(style: .file, allowedUnits: [.kb, .mb, .gb, .tb], spellsOutZero: true)
            .locale(locale)))
    }

    /// Compact uptime since a start date, e.g. "5h 14m", "3d 2h", "just now".
    static func uptime(since date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "just now" }
        let m = s / 60, h = m / 60, d = h / 24
        if d > 0 { return "\(d)d \(h % 24)h" }
        if h > 0 { return "\(h)h \(m % 60)m" }
        return "\(m)m"
    }

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        // Treat a missing date — or the Unix-epoch sentinel the engine substitutes
        // when an image records no creation time (reproducibly-built infra images
        // like `vminit` carry no `created` field) — as unknown, instead of rendering
        // a misleading "56 yr ago" for a 1970-01-01 fallback.
        guard let date, date.timeIntervalSince1970 > 86_400 else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: now)
    }

    /// `relative(_:)` from a raw RFC-3339 string (OCI image history entries),
    /// with or without fractional seconds. Empty input renders the dash;
    /// unparseable input passes through verbatim.
    static func relative(iso8601 raw: String, now: Date = Date()) -> String {
        guard !raw.isEmpty else { return "—" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
            return raw
        }
        return relative(date, now: now)
    }

    /// Short percentage from a 0...1 fraction, e.g. "43%" (en) / "43 %" (de).
    static func percent(_ fraction: Double, locale: Locale = .autoupdatingCurrent) -> String {
        percent(points: fraction * 100, digits: 0, locale: locale)
    }

    /// Percentage from percent points (0.8 → "0.8%" en / "0,8 %" de). Points may
    /// exceed 100 — CPU load is summed across containers/cores.
    static func percent(points: Double, digits: Int = 1, locale: Locale = .autoupdatingCurrent) -> String {
        narrowUnitSpace((points / 100).formatted(
            .percent.precision(.fractionLength(digits)).locale(locale)))
    }

    /// Replace the space separating a value from its trailing unit with a
    /// narrow no-break space. Only the last (no-break) space is touched, so
    /// grouping separators inside the number survive; idempotent when the
    /// formatter already emitted a narrow space.
    static func narrowUnitSpace(_ s: String) -> String {
        guard let idx = s.lastIndex(where: { $0 == " " || $0 == "\u{00A0}" || $0 == "\u{202F}" }) else { return s }
        return s.replacingCharacters(in: idx...idx, with: "\u{202F}")
    }

    /// One user-facing line for an error: the LocalizedError description when
    /// the error provides one, otherwise the default interpolation.
    static func error(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }

    /// Pretty-printed JSON for the Inspect tabs — deterministic key order,
    /// ISO-8601 dates.
    static func prettyJSON(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "Failed to encode."
        }
        return text
    }
}
