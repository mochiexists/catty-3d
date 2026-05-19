// Regression net for PaneSlot — the spatial identity every pane and the
// 3D scene's plane layout agree on.
//
// worldPosition encodes the magic geometry constants (plane 1.6 × 1.05,
// gap 0.05) that are currently duplicated across the renderer. These
// assertions LOCK the exact spacing so the planned SceneMetrics
// extraction (Phase 1 of the OSS refactor) is provably behavior-
// preserving: if a refactor changes a pane's world position by even an
// epsilon, this fails.

import XCTest

#if os(macOS)
@testable import Catty

final class PaneSlotTests: XCTestCase {

    func testOriginIsZeroZero() {
        XCTAssertEqual(PaneSlot.origin, PaneSlot(row: 0, column: 0))
        XCTAssertEqual(PaneSlot.origin.worldPosition, SIMD3<Float>(0, 0, 0))
    }

    func testWorldPositionLocksGridSpacing() {
        // planeW + gap = 1.65 (X step), planeH + gap = 1.10 (Y step), z = 0.
        let right = PaneSlot(row: 0, column: 1).worldPosition
        XCTAssertEqual(right.x, 1.65, accuracy: 1e-5)
        XCTAssertEqual(right.y, 0, accuracy: 1e-5)
        XCTAssertEqual(right.z, 0, accuracy: 1e-5)

        let up = PaneSlot(row: 1, column: 0).worldPosition
        XCTAssertEqual(up.y, 1.10, accuracy: 1e-5)

        let diag = PaneSlot(row: -2, column: 3).worldPosition
        XCTAssertEqual(diag.x, 3 * 1.65, accuracy: 1e-5)
        XCTAssertEqual(diag.y, -2 * 1.10, accuracy: 1e-5)
    }

    func testRawValueRoundTrips() {
        for slot in [PaneSlot(row: 0, column: 0),
                     PaneSlot(row: 7, column: -3),
                     PaneSlot(row: -12, column: 9)] {
            XCTAssertEqual(PaneSlot(rawValue: slot.rawValue), slot)
        }
        XCTAssertNil(PaneSlot(rawValue: "garbage"))
        XCTAssertNil(PaneSlot(rawValue: "r1x2"))
    }

    func testNeighboursAreTheFourCardinals() {
        let n = PaneSlot(row: 2, column: 5).neighbours()
        XCTAssertEqual(Set(n), Set([
            PaneSlot(row: 3, column: 5),
            PaneSlot(row: 1, column: 5),
            PaneSlot(row: 2, column: 4),
            PaneSlot(row: 2, column: 6)
        ]))
        XCTAssertEqual(n.count, 4)
    }

    func testCodableRoundTrip() throws {
        let slot = PaneSlot(row: -4, column: 11)
        let data = try JSONEncoder().encode(slot)
        XCTAssertEqual(try JSONDecoder().decode(PaneSlot.self, from: data), slot)
    }
}
#endif
