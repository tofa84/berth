//
//  PruneSummaryTests.swift
//  berthTests
//

import Testing
@testable import berth

struct PruneSummaryTests {

    @Test func emptyIsNil() {
        #expect(pruneSummary([], of: 3, noun: "images") == nil)
    }

    @Test func singleFailureVerbatim() {
        #expect(pruneSummary(["boom"], of: 3, noun: "images") == "boom")
    }

    @Test func aggregatesMultiple() {
        #expect(pruneSummary(["a", "b"], of: 5, noun: "volumes") == "2 of 5 volumes failed: a; b")
    }
}
