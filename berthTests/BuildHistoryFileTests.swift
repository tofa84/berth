//
//  BuildHistoryFileTests.swift
//  berthTests
//
//  Layer-A: the build-history JSON round-trips, keeps newest-first with a cap,
//  and degrades to empty on a missing/corrupt file.
//

import Testing
import Foundation
@testable import berth

struct BuildHistoryFileTests {
    private func tempFile() -> BuildHistoryFile {
        BuildHistoryFile(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func record(_ tag: String) -> BuildRecord {
        BuildRecord(
            id: UUID(), date: Date(),
            request: BuildRequest(contextDir: "/ctx", dockerfilePath: "/ctx/Dockerfile", tags: [tag]),
            outcome: .succeeded(tags: [tag]), duration: 1.5)
    }

    @Test func missingFileLoadsEmpty() {
        #expect(tempFile().load().isEmpty)
    }

    @Test func appendRoundTripsNewestFirst() throws {
        let file = tempFile()
        try file.append(record("a:1"))
        try file.append(record("b:2"))
        let loaded = file.load()
        #expect(loaded.count == 2)
        #expect(loaded[0].primaryTag == "b:2")  // newest first
        #expect(loaded[1].primaryTag == "a:1")
    }

    @Test func capKeepsNewest() throws {
        let file = tempFile()
        for i in 0..<60 { try file.append(record("t:\(i)"), keeping: 50) }
        let loaded = file.load()
        #expect(loaded.count == 50)
        #expect(loaded.first?.primaryTag == "t:59")  // newest
        #expect(loaded.last?.primaryTag == "t:10")   // oldest kept
    }

    @Test func corruptFileLoadsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("build-history.json"))
        #expect(BuildHistoryFile(directory: dir).load().isEmpty)
    }

    @Test func outcomesRoundTrip() throws {
        let file = tempFile()
        let failed = BuildRecord(id: UUID(), date: Date(),
            request: BuildRequest(contextDir: "/c", dockerfilePath: "/c/Dockerfile", tags: ["x"]),
            outcome: .failed(message: "boom"), duration: 2)
        let cancelled = BuildRecord(id: UUID(), date: Date(),
            request: BuildRequest(contextDir: "/c", dockerfilePath: "/c/Dockerfile", tags: ["y"]),
            outcome: .cancelled, duration: 0.3)
        try file.append(failed)
        try file.append(cancelled)
        let loaded = file.load()
        #expect(loaded[0].outcome == .cancelled)
        #expect(loaded[1].outcome == .failed(message: "boom"))
    }
}
