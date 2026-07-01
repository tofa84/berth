//
//  SystemControlErrorTests.swift
//  berthTests
//

import Testing
@testable import berth

struct SystemControlErrorTests {

    @Test func binaryNotFoundMentionsContainer() {
        let msg = SystemControlError.binaryNotFound.errorDescription
        #expect(msg?.contains("container") == true)
    }

    @Test func commandFailedPassesMessageThrough() {
        #expect(SystemControlError.commandFailed("exit 1").errorDescription == "exit 1")
    }
}
