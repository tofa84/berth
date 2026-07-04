//
//  BuildProgress.swift
//  berth
//
//  Pure parsing of BuildKit plain-progress output (what the builder shim emits
//  when we ask for `progress=plain`) into a structured step list. Grammar was
//  locked against real captured output (M0 PoC). Everything here is pure and
//  `nonisolated` so it is hermetically Layer-A testable; unrecognized lines
//  degrade to the raw log, so the structured view can never break.
//
//  Line shapes (see the M0 transcript):
//    #5 [linux/arm64 1/3] RUN echo hi   → first line for a vertex id: its title
//    #5 0.035 hi                        → subsequent line for that id: detail
//    #5 DONE 1.2s                       → terminal: done (with duration)
//    #6 CACHED                          → terminal: cached
//    #7 ERROR: process "…" exit code: 1 → terminal: error
//    ------ /  > [..]: / (blank)        → not a #id line: plain (error excerpts)
//

import Foundation

enum BuildProgressParser {
    /// One classified line. `vertex` is any non-terminal `#id` line; the folder
    /// decides whether it is the title (first seen) or a detail line.
    enum Line: Equatable, Sendable {
        case vertex(id: Int, text: String)
        case done(id: Int, seconds: Double?)
        case cached(id: Int)
        case canceled(id: Int)
        case error(id: Int, message: String)
        case plain(String)
    }

    static func classify(_ raw: String) -> Line {
        let line = strippingANSI(raw)
        guard line.hasPrefix("#") else { return .plain(line) }

        let afterHash = line.dropFirst()
        let digits = afterHash.prefix { $0.isNumber }
        guard !digits.isEmpty, let id = Int(digits) else { return .plain(line) }

        var rest = afterHash.dropFirst(digits.count)
        guard rest.hasPrefix(" ") else { return .plain(line) }
        rest.removeFirst()
        let text = String(rest)

        if text == "CACHED" { return .cached(id: id) }
        if text == "CANCELED" || text == "CANCELLED" { return .canceled(id: id) }
        if text == "DONE" || text.hasPrefix("DONE ") {
            return .done(id: id, seconds: parseSeconds(text.dropFirst(4)))
        }
        if text.hasPrefix("ERROR") {
            var message = Substring(text.dropFirst(5))
            if message.hasPrefix(":") { message = message.dropFirst() }
            return .error(id: id, message: message.trimmingCharacters(in: .whitespaces))
        }
        return .vertex(id: id, text: text)
    }

    /// Parses the seconds out of a `DONE 1.2s` tail (the substring after "DONE").
    private static func parseSeconds(_ tail: Substring) -> Double? {
        let token = tail.trimmingCharacters(in: .whitespaces)
        guard token.hasSuffix("s") else { return Double(token) }
        return Double(token.dropLast())
    }

    /// Strips ANSI CSI escape sequences and carriage returns. Plain mode is
    /// escape-free in practice, but this keeps the parser robust if it isn't.
    static func strippingANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") || s.contains("\r") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var iterator = s.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }
        while let ch = next() {
            if ch == "\r" { continue }
            if ch == "\u{1B}" {
                // Consume "[ … <final letter>" (CSI). Drop the whole sequence.
                guard let bracket = iterator.next() else { break }
                if bracket == "[" {
                    while let c = iterator.next() {
                        if c.isLetter { break }
                    }
                } else {
                    // Not a CSI we recognize — keep the following char.
                    pending = bracket
                }
                continue
            }
            out.append(ch)
        }
        return out
    }
}

/// Folds a stream of plain-progress lines into an ordered step list plus any
/// trailing free-text (error excerpts). Value type — the store holds one and
/// feeds it line by line.
struct BuildStepFolder: Sendable {
    struct Step: Identifiable, Equatable, Sendable {
        enum State: Equatable, Sendable {
            case running
            case done(seconds: Double?)
            case cached
            case error(String)
            case canceled
        }
        let id: Int
        var title: String
        var state: State
        var detail: [String]
    }

    private(set) var steps: [Step] = []
    private(set) var trailing: [String] = []
    private static let detailCap = 50

    var isEmpty: Bool { steps.isEmpty && trailing.isEmpty }

    mutating func ingest(_ raw: String) {
        switch BuildProgressParser.classify(raw) {
        case .vertex(let id, let text):
            if let idx = steps.firstIndex(where: { $0.id == id }) {
                steps[idx].detail.append(text)
                let overflow = steps[idx].detail.count - Self.detailCap
                if overflow > 0 { steps[idx].detail.removeFirst(overflow) }
            } else {
                steps.append(Step(id: id, title: text, state: .running, detail: []))
            }
        case .done(let id, let seconds):
            setState(id, .done(seconds: seconds))
        case .cached(let id):
            setState(id, .cached)
        case .canceled(let id):
            setState(id, .canceled)
        case .error(let id, let message):
            setState(id, .error(message))
        case .plain(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { trailing.append(trimmed) }
        }
    }

    private mutating func setState(_ id: Int, _ state: Step.State) {
        if let idx = steps.firstIndex(where: { $0.id == id }) {
            steps[idx].state = state
        } else {
            steps.append(Step(id: id, title: "#\(id)", state: state, detail: []))
        }
    }
}
