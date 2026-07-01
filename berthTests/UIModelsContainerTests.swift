//
//  UIModelsContainerTests.swift
//  berthTests
//
//  Pure `ContainerSnapshot` view-model accessors from UIModels.swift, driven by
//  Fixtures.snapshot (public inits, no engine).
//

import Testing
import Foundation
@testable import berth

struct UIModelsContainerTests {

    @Test func shortID() throws {
        let s = try Fixtures.snapshot(id: "abcdef0123456789aaaa")
        #expect(s.shortID == "abcdef012345")
    }

    @Test func portsSummaryEmpty() throws {
        let s = try Fixtures.snapshot(ports: [])
        #expect(s.portsSummary == "—")
    }

    @Test func portsSummary() throws {
        let s = try Fixtures.snapshot(ports: [(8080, 80, false), (53, 53, true)])
        #expect(s.portsSummary == "8080:80, 53:53")
    }

    @Test func primaryIPStripsCIDR() throws {
        let s = try Fixtures.snapshot(ipv4: "192.168.64.2/24")
        #expect(s.primaryIP == "192.168.64.2")
    }

    @Test func primaryIPNilWhenNoNetwork() throws {
        let s = try Fixtures.snapshot(ipv4: nil)
        #expect(s.primaryIP == nil)
    }

    @Test func osArchAndResources() throws {
        let s = try Fixtures.snapshot(os: "linux", arch: "arm64", cpus: 4, memBytes: 2 << 30)
        #expect(s.osArch == "linux/arm64")
        #expect(s.allocatedCPUs == 4)
        #expect(s.memoryLimitBytes == 2 << 30)
        #expect(s.isRunning == true)
    }

    @Test func command() throws {
        let s = try Fixtures.snapshot(exec: "/bin/sh", args: ["-c", "echo hi"])
        #expect(s.command == "/bin/sh -c echo hi")
    }
}
