//
//  LogReaderTests.swift
//  berthTests
//
//  Drives the whole log-streaming pipeline over real OS pipes — no engine, no
//  container. Covers newline splitting, stdout/stderr tagging (fd index 1 ==
//  stderr), the trailing-partial-line flush on stop, and the terminal sentinel.
//

import Testing
import Foundation
@testable import berth

struct LogReaderTests {

    /// Runs ~2s: the reader idles with a doubling backoff (300 → 1500 ms) before
    /// it first consults `isStopped()`, which is when the trailing partial line is
    /// flushed and the loops exit.
    @Test(.timeLimit(.minutes(1)))
    func streamingPipeline() async throws {
        let out = Pipe()
        let err = Pipe()

        out.fileHandleForWriting.write(Data("line1\nline2\npartial".utf8))
        err.fileHandleForWriting.write(Data("errline\n".utf8))
        try out.fileHandleForWriting.close()
        try err.fileHandleForWriting.close()

        let (stream, continuation) = AsyncStream.makeStream(of: LogLine.self)
        let pump = Task {
            // fd index 1 is tagged stderr; the container is already "stopped".
            await LogReader.pump(
                [out.fileHandleForReading, err.fileHandleForReading],
                isStopped: { true },
                into: continuation)
            continuation.finish()
        }

        var stdout: [String] = []
        var stderr: [String] = []
        var sawSentinel = false
        for await line in stream {
            switch line.kind {
            case .stdout:
                if line.text == "—— container stopped ——" { sawSentinel = true }
                else { stdout.append(line.text) }
            case .stderr:
                stderr.append(line.text)
            }
        }
        await pump.value

        #expect(stdout.contains("line1"))
        #expect(stdout.contains("line2"))
        #expect(stdout.contains("partial"))     // trailing partial line flushed on stop
        #expect(stderr.contains("errline"))
        #expect(sawSentinel)
    }
}
