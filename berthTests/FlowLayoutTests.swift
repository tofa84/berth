//
//  FlowLayoutTests.swift
//  berthTests
//
//  Pure wrap math lifted out of FlowLayout's Layout conformance.
//

import Testing
import CoreGraphics
@testable import berth

struct FlowLayoutTests {

    @Test func singleRowWhenEverythingFits() {
        let sizes = [CGSize(width: 20, height: 10), CGSize(width: 30, height: 12)]
        let laid = FlowLayout.arrange(sizes: sizes, maxWidth: 200, spacing: 6)
        #expect(laid.positions[0] == CGPoint(x: 0, y: 0))
        #expect(laid.positions[1] == CGPoint(x: 26, y: 0))   // 20 + 6 spacing
        #expect(laid.size.height == 12)                      // tallest item in the single row
    }

    @Test func wrapsWhenNextItemExceedsMaxWidth() {
        let sizes = Array(repeating: CGSize(width: 60, height: 10), count: 3)
        // maxWidth 130: item0 @x0, item1 @x66 (66+60=126 ≤ 130). item2 would start
        // at x132 → 132+60 > 130 && x>0 → wraps to a new row at x0.
        let laid = FlowLayout.arrange(sizes: sizes, maxWidth: 130, spacing: 6)
        #expect(laid.positions[0].y == 0)
        #expect(laid.positions[1].y == 0)
        #expect(laid.positions[2].x == 0)
        #expect(laid.positions[2].y > 0)
        #expect(laid.size.height == 26)                      // row1 (10) + spacing (6) + row2 (10)
    }
}
