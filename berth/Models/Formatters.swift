//
//  Formatters.swift
//  berth
//
//  Pure formatting helpers (bytes, durations, dates). No engine access.
//

import Foundation

enum Format {
    /// Human byte size, e.g. 1.2 GB / 320 MB.
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return bytes(Int64(min(value, UInt64(Int64.max))))
    }

    static func bytes(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: value)
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
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: now)
    }

    /// Short percentage from a 0...1 fraction.
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
