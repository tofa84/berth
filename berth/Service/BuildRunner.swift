//
//  BuildRunner.swift
//  berth
//
//  Native gRPC build executor. Adapted from apple/container 1.0.0
//  Sources/ContainerBuild/Builder.swift (Apache-2.0; upstream license header
//  retained below). berth vendors this thin runner instead of calling the
//  upstream `Builder.build(_:)` for two reasons:
//
//   1. Progress capture. Upstream hardwires the PerformBuild `progress` metadata
//      to "tty" whenever a Terminal is attached, and its BuildPipeline writes all
//      build output to `config.terminal?.handle ?? stderr`. A GUI has no tty. We
//      send `progress=plain` and attach a pipe-backed Terminal (built with
//      setInitState:false so wrapping a pipe fd doesn't throw on tcgetattr), so
//      plain, parseable progress text lands in a berth-owned pipe.
//
//   2. Deterministic teardown. Upstream releases the gRPC client + EventLoopGroup
//      only inside a `catch Error.buildComplete` block, but that error is never
//      thrown in 1.0.0 — so a long-lived GUI would leak an EventLoopGroup and a
//      `runConnections` task per build. `shutdown()` here always runs.
//
//  Everything heavy stays upstream: we reuse the public `BuildPipeline`,
//  `Builder.BuildConfig`, the generated gRPC client, and `ClientStream` /
//  `ServerStream`. When bumping the apple/container SPM pin, re-diff against the
//  upstream Builder.swift at the new tag — the `metadata(_:)` copy and the
//  connection wiring below are the drift-sensitive parts.
//
//===----------------------------------------------------------------------===//
// Portions Copyright © 2025-2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ContainerBuild
import ContainerizationOCI
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Logging
import NIOCore
import NIOPosix

/// A single-use native gRPC build executor. Dial `buildkit:8088`, hand the
/// connected vsock `FileHandle` here, run one build, then `shutdown()`.
nonisolated struct BuildRunner: Sendable {
    private let client: Com_Apple_Container_Build_V1_Builder.Client<HTTP2ClientTransport.WrappedChannel>
    private let grpcClient: GRPCClient<HTTP2ClientTransport.WrappedChannel>
    private let group: MultiThreadedEventLoopGroup
    private let socket: FileHandle
    private let clientTask: Task<Void, any Swift.Error>
    private let logger: Logger

    enum Failure: Swift.Error, CustomStringConvertible {
        case invalidContinuation
        var description: String {
            switch self {
            case .invalidContinuation: return "request continuation could not be created"
            }
        }
    }

    init(socket: FileHandle, logger: Logger) throws {
        try socket.berthSetSendBufSize(4 << 20)
        try socket.berthSetRecvBufSize(2 << 20)

        // A build is a single bidirectional stream; two loops are plenty for a GUI.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)

        let channel = try ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture(withResultOf: {
                    try channel.pipeline.syncOperations.addHandler(HTTP2ConnectBufferingHandler())
                })
            }
            .withConnectedSocket(socket.fileDescriptor)
            .wait()

        let transport = HTTP2ClientTransport.WrappedChannel.wrapping(channel: channel)
        let grpcClient = GRPCClient(transport: transport)

        self.grpcClient = grpcClient
        self.client = Com_Apple_Container_Build_V1_Builder.Client(wrapping: grpcClient)
        self.group = group
        self.socket = socket
        self.logger = logger

        // Drive the client connection loop in the background.
        self.clientTask = Task {
            do {
                try await grpcClient.runConnections()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RPCError where error.code == .unavailable {
                // Connection closed — expected when the builder stops or we tear down.
                logger.debug("gRPC connection closed: \(error)")
                throw error
            } catch {
                logger.error("gRPC client connection error: \(error)")
                throw error
            }
        }
    }

    /// Liveness probe — a successful `Info` means BuildKit is listening on the vsock.
    func info() async throws {
        var opts = CallOptions.defaults
        opts.timeout = .seconds(30)
        _ = try await self.client.info(InfoRequest(), options: opts)
    }

    /// Run one build to completion. Returns normally when the server closes the
    /// response stream — note a *failed* build (e.g. a non-zero `RUN`) also
    /// returns normally: no handler in the upstream pipeline consumes the
    /// `buildError` packet, so failure surfaces as a missing image export, not a
    /// thrown error. Throws only on transport/cancellation errors.
    func run(_ config: Builder.BuildConfig) async throws {
        var continuation: AsyncStream<ClientStream>.Continuation?
        let reqStream = AsyncStream<ClientStream> { cont in continuation = cont }
        guard let continuation else { throw Failure.invalidContinuation }
        defer { continuation.finish() }

        // The upstream SIGWINCH task is intentionally dropped: we attach a
        // pipe-backed Terminal whose `size` would throw, and a GUI has no window
        // size to forward anyway.
        let pipeline = try await BuildPipeline(config)
        try await self.client.performBuild(
            metadata: try Self.metadata(config),
            options: .defaults,
            requestProducer: { writer in
                for await message in reqStream {
                    try await writer.write(message)
                }
            },
            onResponse: { response in
                try await pipeline.run(sender: continuation, receiver: response.messages)
            }
        )
    }

    /// Always call after `run` (on success, failure, or cancellation) to release
    /// the gRPC client and EventLoopGroup — the upstream teardown path is dead
    /// code in 1.0.0 and would otherwise leak both per build.
    func shutdown() async {
        grpcClient.beginGracefulShutdown()
        clientTask.cancel()
        _ = try? await clientTask.value
        try? await group.shutdownGracefully()
    }

    /// Copied from upstream `Builder.buildMetadata`, with `progress` forced to
    /// "plain" (see the file header). Keys must match the builder-shim contract;
    /// re-diff on every SPM bump.
    static func metadata(_ config: Builder.BuildConfig) throws -> Metadata {
        var metadata = Metadata()
        metadata.addString(config.buildID, forKey: "build-id")
        metadata.addString(URL(filePath: config.contextDir).path(percentEncoded: false), forKey: "context")
        metadata.addString(config.dockerfile.base64EncodedString(), forKey: "dockerfile")
        metadata.addString("plain", forKey: "progress")
        metadata.addString(config.target, forKey: "target")

        if let dockerignore = config.dockerignore {
            metadata.addString(dockerignore.base64EncodedString(), forKey: "dockerignore")
        }
        for tag in config.tags {
            metadata.addString(tag, forKey: "tag")
        }
        for platform in config.platforms {
            metadata.addString(platform.description, forKey: "platforms")
        }
        if config.noCache {
            metadata.addString("", forKey: "no-cache")
        }
        for label in config.labels {
            metadata.addString(label, forKey: "labels")
        }
        for buildArg in config.buildArgs {
            metadata.addString(buildArg, forKey: "build-args")
        }
        for (id, data) in config.secrets {
            metadata.addString(id + "=" + data.base64EncodedString(), forKey: "secrets")
        }
        for output in config.exports {
            metadata.addString(try output.stringValue, forKey: "outputs")
        }
        for cacheIn in config.cacheIn {
            metadata.addString(cacheIn, forKey: "cache-in")
        }
        for cacheOut in config.cacheOut {
            metadata.addString(cacheOut, forKey: "cache-out")
        }
        return metadata
    }
}

// Copied verbatim from upstream Builder.swift (the module-internal helpers are
// not visible to berth): socket buffer sizing + the HTTP/2 connect buffer.

extension FileHandle {
    @discardableResult
    fileprivate func berthSetSendBufSize(_ bytes: Int) throws -> Int {
        try berthSetSockOpt(level: SOL_SOCKET, name: SO_SNDBUF, value: bytes)
        return bytes
    }

    @discardableResult
    fileprivate func berthSetRecvBufSize(_ bytes: Int) throws -> Int {
        try berthSetSockOpt(level: SOL_SOCKET, name: SO_RCVBUF, value: bytes)
        return bytes
    }

    private func berthSetSockOpt(level: Int32, name: Int32, value: Int) throws {
        var v = Int32(value)
        let res = withUnsafePointer(to: &v) { ptr -> Int32 in
            ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<Int32>.size) { raw in
                setsockopt(self.fileDescriptor, level, name, raw, socklen_t(MemoryLayout<Int32>.size))
            }
        }
        if res == -1 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }
    }
}

/// Buffers incoming bytes until the full gRPC HTTP/2 pipeline is configured,
/// then replays them. Copied from upstream Builder.swift (private there).
private final class HTTP2ConnectBufferingHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var removalScheduled = false
    private var bufferedReads: [NIOAny] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        bufferedReads.append(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {}

    func flush(context: ChannelHandlerContext) {
        if !removalScheduled {
            removalScheduled = true
            context.eventLoop.assumeIsolatedUnsafeUnchecked().execute {
                context.pipeline.syncOperations.removeHandler(self, promise: nil)
            }
        }
        context.flush()
    }

    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        var didRead = false
        while !bufferedReads.isEmpty {
            context.fireChannelRead(bufferedReads.removeFirst())
            didRead = true
        }
        if didRead {
            context.fireChannelReadComplete()
        }
        context.leavePipeline(removalToken: removalToken)
    }

    func channelInactive(context: ChannelHandlerContext) {
        bufferedReads.removeAll()
        context.fireChannelInactive()
    }
}
