//
//  BarChartTests.swift
//  berthTests
//
//  Pure right-aligned sampling lifted out of BarChart.value(at:).
//

import Testing
@testable import berth

struct BarChartTests {

    @Test func rightAlignsSamples() {
        let values = [0.5, 0.8]
        // slots 4, count 2 → offset 2: indices 0,1 are empty; 2,3 map to values 0,1.
        #expect(BarChart.sample(values: values, slots: 4, at: 0) == nil)
        #expect(BarChart.sample(values: values, slots: 4, at: 1) == nil)
        #expect(BarChart.sample(values: values, slots: 4, at: 2) == 0.5)
        #expect(BarChart.sample(values: values, slots: 4, at: 3) == 0.8)
    }

    @Test func clampsToUnitRange() {
        #expect(BarChart.sample(values: [1.5], slots: 1, at: 0) == 1.0)
        #expect(BarChart.sample(values: [-0.3], slots: 1, at: 0) == 0.0)
    }
}
