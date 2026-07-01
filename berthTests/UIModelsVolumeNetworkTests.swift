//
//  UIModelsVolumeNetworkTests.swift
//  berthTests
//

import Testing
@testable import berth

struct UIModelsVolumeNetworkTests {

    @Test func volumeMountPointAndSize() {
        let v = Fixtures.volume(name: "data", source: "/mnt/data", sizeInBytes: 5 * 1024 * 1024)
        #expect(v.mountPoint == "/mnt/data")
        #expect(v.sizeText != "—")            // delegates to Format.bytes (locale-dependent)
    }

    @Test func volumeSizeTextNilWhenUnknown() {
        let v = Fixtures.volume(sizeInBytes: nil)
        #expect(v.sizeText == "—")
    }

    @Test func networkDriverLabelStripsPrefix() throws {
        let n = try Fixtures.network(plugin: "container-network-vmnet")
        #expect(n.driverLabel == "vmnet")
    }

    @Test func networkSubnetAndGateway() throws {
        let n = try Fixtures.network(subnet: "192.168.64.0/24", gateway: "192.168.64.1")
        #expect(n.subnetText == "192.168.64.0/24")
        #expect(n.gatewayText == "192.168.64.1")
    }
}
