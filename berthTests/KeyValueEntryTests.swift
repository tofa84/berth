//
//  KeyValueEntryTests.swift
//  berthTests
//
//  `KeyValueEntry.split` is the pure seam behind every KEY=VALUE list (env
//  vars, build args, labels): entries split at the *first* `=` so values
//  containing `=` stay intact. `KeyValueField(entry:)` is the form-row
//  projection of the same rule.
//

import Testing
@testable import berth

struct KeyValueEntryTests {

    @Test func splitsAtFirstEquals() {
        let (key, value) = KeyValueEntry.split("HOME=/var/lib/rabbitmq")
        #expect(key == "HOME")
        #expect(value == "/var/lib/rabbitmq")
    }

    @Test func valueKeepsLaterEquals() {
        let (key, value) = KeyValueEntry.split("JAVA_OPTS=-Xms=256m -Xmx=1g")
        #expect(key == "JAVA_OPTS")
        #expect(value == "-Xms=256m -Xmx=1g")
    }

    @Test func missingEqualsBecomesBareKey() {
        let (key, value) = KeyValueEntry.split("STANDALONE")
        #expect(key == "STANDALONE")
        #expect(value == "")
    }

    @Test func emptyValue() {
        let (key, value) = KeyValueEntry.split("DEBUG=")
        #expect(key == "DEBUG")
        #expect(value == "")
    }

    @Test func leadingEquals() {
        // Degenerate but must not crash or lose the remainder.
        let (key, value) = KeyValueEntry.split("=weird")
        #expect(key == "")
        #expect(value == "weird")
    }

    @Test func fieldParsesEntry() {
        let field = KeyValueField(entry: "VER=1.2=rc")
        #expect(field.key == "VER")
        #expect(field.value == "1.2=rc")
    }
}
