//
//  EngineVersionTests.swift
//  berthTests
//
//  Pure semver extraction lifted out of EngineConnection.version.
//

import Testing
@testable import berth

struct EngineVersionTests {

    @Test func extractsFromVerboseString() {
        #expect(EngineConnection.parseVersion(from: "container-apiserver version 1.0.0 (build: release)") == "1.0.0")
    }

    @Test func passesThroughBareVersion() {
        #expect(EngineConnection.parseVersion(from: "1.0.0") == "1.0.0")
    }

    @Test func fallsBackToRawWhenNoMatch() {
        #expect(EngineConnection.parseVersion(from: "weird") == "weird")
    }
}
