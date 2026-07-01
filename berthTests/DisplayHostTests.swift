//
//  DisplayHostTests.swift
//  berthTests
//
//  Pure ".local"-suffix stripping lifted out of DisplayHost.name.
//

import Testing
@testable import berth

struct DisplayHostTests {

    @Test func stripsLocalSuffix() {
        #expect(DisplayHost.displayName(from: "MacBook.local") == "MacBook")
    }

    @Test func leavesPlainNameUntouched() {
        #expect(DisplayHost.displayName(from: "host") == "host")
    }

    @Test func bareLocalBecomesEmpty() {
        #expect(DisplayHost.displayName(from: ".local") == "")
    }
}
