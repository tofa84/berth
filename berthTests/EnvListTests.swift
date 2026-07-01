//
//  EnvListTests.swift
//  berthTests
//
//  `EnvList.split` is the pure seam behind the environment key-value list:
//  entries split at the *first* `=` so values containing `=` stay intact.
//

import Testing
@testable import berth

struct EnvListTests {

    @Test func splitsAtFirstEquals() {
        let (key, value) = EnvList.split("HOME=/var/lib/rabbitmq")
        #expect(key == "HOME")
        #expect(value == "/var/lib/rabbitmq")
    }

    @Test func valueKeepsLaterEquals() {
        let (key, value) = EnvList.split("JAVA_OPTS=-Xms=256m -Xmx=1g")
        #expect(key == "JAVA_OPTS")
        #expect(value == "-Xms=256m -Xmx=1g")
    }

    @Test func missingEqualsBecomesBareKey() {
        let (key, value) = EnvList.split("STANDALONE")
        #expect(key == "STANDALONE")
        #expect(value == "")
    }

    @Test func emptyValue() {
        let (key, value) = EnvList.split("DEBUG=")
        #expect(key == "DEBUG")
        #expect(value == "")
    }

    @Test func leadingEquals() {
        // Degenerate but must not crash or lose the remainder.
        let (key, value) = EnvList.split("=weird")
        #expect(key == "")
        #expect(value == "weird")
    }
}
