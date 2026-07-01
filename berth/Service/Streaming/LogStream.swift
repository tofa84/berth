//
//  LogStream.swift
//  berth
//
//  Reads a container's stdout/stderr log file handles as an AsyncStream of
//  tagged lines. The runtime writes container output to growing files, so we
//  poll for appended data and split on newlines. Pure Sendable values cross
//  back to the MainActor model.
//

import Foundation

enum LogKind: Sendable {
    case stdout, stderr
}

struct LogLine: Sendable {
    let text: String
    let kind: LogKind

    /// End-of-stream marker yielded once both read loops have exited; the log
    /// view styles it distinctly (see `LogFormat.parse`).
    static let stoppedSentinel = "—— container stopped ——"
}

enum LogReader {
    /// Pump both handles concurrently into the continuation until cancelled or
    /// the container has exited (after which the log files never grow again).
    static func pump(
        _ handles: [FileHandle],
        isStopped: @escaping @Sendable () async -> Bool,
        into continuation: AsyncStream<LogLine>.Continuation
    ) async {
        let fds = handles.map { $0.fileDescriptor }   // Int32 is Sendable; avoids crossing FileHandle
        await withTaskGroup(of: Void.self) { group in
            for (idx, fd) in fds.enumerated() {
                let kind: LogKind = (idx == 1) ? .stderr : .stdout
                group.addTask { await readLoop(fd: fd, kind: kind, isStopped: isStopped, into: continuation) }
            }
        }
        // Both loops exit on their own only once the container has stopped;
        // cancellation (tab/view change) is the other way out. Mark the end so
        // the user knows no further output is coming.
        if !Task.isCancelled {
            continuation.yield(LogLine(text: LogLine.stoppedSentinel, kind: .stdout))
        }
    }

    private static func readLoop(
        fd: Int32,
        kind: LogKind,
        isStopped: @escaping @Sendable () async -> Bool,
        into continuation: AsyncStream<LogLine>.Continuation
    ) async {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var buffer = Data()
        let newline: UInt8 = 0x0A
        var idleMillis = 300   // backoff while no new data arrives (capped below)
        while !Task.isCancelled {
            let chunk = (try? handle.read(upToCount: 16 * 1024)) ?? nil
            guard let chunk, !chunk.isEmpty else {
                // No new data. Back off, and once fully backed off, check whether
                // the container has exited — if so, flush any trailing partial
                // line and stop instead of polling the file at EOF forever.
                if idleMillis >= 1500, await isStopped() {
                    if !buffer.isEmpty {
                        continuation.yield(LogLine(text: String(decoding: buffer, as: UTF8.self), kind: kind))
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(idleMillis))
                idleMillis = min(idleMillis * 2, 1500)
                continue
            }
            idleMillis = 300   // data flowing again; resume fast polling
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: newline) {
                let lineData = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                let text = String(decoding: lineData, as: UTF8.self)
                continuation.yield(LogLine(text: text, kind: kind))
            }
        }
    }
}
