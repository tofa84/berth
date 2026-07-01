//
//  LogFormat.swift
//  berth
//
//  Pure presentation-side parsing of raw container log lines into
//  timestamp / level / message parts, so the log view can dim timestamps,
//  give levels a fixed column, and color by severity (amber = warning,
//  red = error). Container output is arbitrary text, so detection is
//  conservative: anything unrecognized degrades to a plain line.
//

import Foundation

/// Presentation severity of one log line.
enum LogSeverity: Equatable, Sendable {
    case neutral, debug, info, warning, error, sentinel
}

/// One log line split for rendering.
struct ParsedLogLine: Equatable, Sendable {
    /// Leading timestamp token, when the line starts with one (kept verbatim).
    let timestamp: String?
    /// Recognized level token, lowercased as it appeared (e.g. "warn", "warning").
    let level: String?
    let severity: LogSeverity
    /// The remaining text (the full line when nothing was recognized).
    let message: String
}

enum LogFormat {
    /// `"08:53:05.726"`-style clock or full ISO-8601 timestamps.
    private nonisolated static let clockToken = /^\d{2}:\d{2}:\d{2}(?:[.,]\d+)?$/
    private nonisolated static let isoToken =
        /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?$/

    nonisolated static func parse(_ text: String, kind: LogKind) -> ParsedLogLine {
        if text == LogLine.stoppedSentinel {
            return ParsedLogLine(timestamp: nil, level: nil, severity: .sentinel, message: text)
        }
        // Stream is the fallback signal: stderr stays red like today.
        let fallback: LogSeverity = (kind == .stderr) ? .error : .neutral
        let plain = ParsedLogLine(timestamp: nil, level: nil, severity: fallback, message: text)

        var rest = text[...]
        var timestamp: String?
        if let (token, remainder) = splitToken(rest), isTimestamp(token) {
            timestamp = String(token)
            rest = remainder
        }

        if let (token, remainder) = splitToken(rest),
           let (level, severity) = level(from: token, timestamped: timestamp != nil) {
            let message = remainder.trimmingCharacters(in: .whitespaces)
            // A level with nothing after it is more likely prose than a header.
            if !message.isEmpty {
                return ParsedLogLine(timestamp: timestamp, level: level, severity: severity, message: message)
            }
        }

        // No level, but a leading timestamp is still worth dimming.
        if let timestamp {
            let message = rest.trimmingCharacters(in: .whitespaces)
            if !message.isEmpty {
                return ParsedLogLine(timestamp: timestamp, level: nil, severity: fallback, message: message)
            }
        }
        return plain
    }

    private nonisolated static func splitToken(_ s: Substring) -> (token: Substring, rest: Substring)? {
        let trimmed = s.drop(while: { $0 == " " || $0 == "\t" })
        guard !trimmed.isEmpty else { return nil }
        let token = trimmed.prefix(while: { $0 != " " && $0 != "\t" })
        return (token, trimmed[token.endIndex...])
    }

    private nonisolated static func isTimestamp(_ token: Substring) -> Bool {
        token.wholeMatch(of: clockToken) != nil || token.wholeMatch(of: isoToken) != nil
    }

    /// Recognize a level token. Without a timestamp anchor only visually marked
    /// tokens count — bracketed, colon-suffixed, or ALL CAPS — so a sentence
    /// like "info about the run" stays plain prose.
    private nonisolated static func level(
        from token: Substring, timestamped: Bool
    ) -> (level: String, severity: LogSeverity)? {
        var t = token
        var marked = false
        if t.hasPrefix("["), t.hasSuffix("]"), t.count > 2 {
            t = t.dropFirst().dropLast()
            marked = true
        }
        if t.hasSuffix(":"), t.count > 1 {
            t = t.dropLast()
            marked = true
        }
        guard !t.isEmpty else { return nil }
        let upper = t.uppercased()
        if !timestamped, !marked, t != upper { return nil }

        let severity: LogSeverity
        switch upper {
        case "TRACE", "DEBUG", "DBG": severity = .debug
        case "INFO", "NOTICE": severity = .info
        case "WARN", "WARNING": severity = .warning
        case "ERROR", "ERR": severity = .error
        case "FATAL", "CRITICAL", "CRIT", "PANIC": severity = .error
        default: return nil
        }
        return (t.lowercased(), severity)
    }
}
