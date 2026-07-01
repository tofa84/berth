//
//  LoadStateTests.swift
//  berthTests
//

import Testing
@testable import berth

struct LoadStateTests {

    @Test func idle() {
        let s = LoadState<[Int]>.idle
        #expect(s.value == nil)
        #expect(s.isLoading == false)
        #expect(s.errorText == nil)
    }

    @Test func loading() {
        let s = LoadState<[Int]>.loading
        #expect(s.isLoading == true)
        #expect(s.value == nil)
        #expect(s.errorText == nil)
    }

    @Test func loaded() {
        let s = LoadState<[Int]>.loaded([1, 2, 3])
        #expect(s.value == [1, 2, 3])
        #expect(s.isLoading == false)
        #expect(s.errorText == nil)
    }

    @Test func failed() {
        let s = LoadState<[Int]>.failed("boom")
        #expect(s.value == nil)
        #expect(s.isLoading == false)
        #expect(s.errorText == "boom")
    }
}
