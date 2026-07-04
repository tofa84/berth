//
//  BuildHistory.swift
//  berth
//
//  Local build history. The engine keeps none, so berth persists a small
//  newest-first list of past builds (request + outcome + duration) as JSON in
//  Application Support, enabling re-run. The file access is pure and the
//  directory is injectable so it's hermetically testable.
//

import Foundation

struct BuildRecord: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let date: Date
    let request: BuildRequest
    let outcome: Outcome
    let duration: TimeInterval

    enum Outcome: Codable, Sendable, Equatable {
        case succeeded(tags: [String])
        case failed(message: String)
        case cancelled
    }

    var primaryTag: String { request.tags.first ?? "(untagged)" }
}

/// Reads/writes the build-history JSON. Value type; `directory` is injected so
/// tests use a temp dir instead of the real Application Support location.
struct BuildHistoryFile: Sendable {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    /// `~/Library/Application Support/de.tomasetti.berth`.
    static let `default` = BuildHistoryFile(
        directory: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("de.tomasetti.berth"))

    private var fileURL: URL { directory.appendingPathComponent("build-history.json") }

    /// Newest-first. Returns an empty list on a missing or corrupt file.
    func load() -> [BuildRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([BuildRecord].self, from: data)) ?? []
    }

    /// Prepend a record and keep at most `max` newest entries.
    func append(_ record: BuildRecord, keeping max: Int = 50) throws {
        var records = load()
        records.insert(record, at: 0)
        if records.count > max { records.removeLast(records.count - max) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
