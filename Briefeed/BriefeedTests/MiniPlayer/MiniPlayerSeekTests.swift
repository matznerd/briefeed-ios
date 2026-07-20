import CoreGraphics
import XCTest
@testable import Briefeed

final class MiniPlayerSeekTests: XCTestCase {
    func testPositionUsesStableGeometryAndClampsToEpisodeBounds() {
        XCTAssertEqual(PlayerSeekGeometry.position(atX: -20, width: 200, duration: 120), 0)
        XCTAssertEqual(PlayerSeekGeometry.position(atX: 50, width: 200, duration: 120), 30)
        XCTAssertEqual(PlayerSeekGeometry.position(atX: 400, width: 200, duration: 120), 120)
        XCTAssertEqual(PlayerSeekGeometry.position(atX: 50, width: 0, duration: 120), 0)
        XCTAssertEqual(PlayerSeekGeometry.position(atX: 50, width: 200, duration: 0), 0)
    }

    func testProgressAndDirectPositionClampInvalidValues() {
        XCTAssertEqual(PlayerSeekGeometry.progress(position: -10, duration: 100), 0)
        XCTAssertEqual(PlayerSeekGeometry.progress(position: 25, duration: 100), 0.25)
        XCTAssertEqual(PlayerSeekGeometry.progress(position: 110, duration: 100), 1)
        XCTAssertEqual(PlayerSeekGeometry.progress(position: .nan, duration: 100), 0)
        XCTAssertEqual(PlayerSeekGeometry.clampedPosition(.infinity, duration: 100), 0)
    }

    func testAccessibilityAdjustmentsUseTenSecondStepsAndClamp() {
        XCTAssertEqual(PlayerSeekGeometry.adjustedPosition(from: 5, direction: .decrement, duration: 100), 0)
        XCTAssertEqual(PlayerSeekGeometry.adjustedPosition(from: 95, direction: .increment, duration: 100), 100)
        XCTAssertEqual(PlayerSeekGeometry.adjustedPosition(from: 40, direction: .increment, duration: 100), 50)
        XCTAssertEqual(PlayerSeekGeometry.adjustmentStep, 10)
    }

    func testScrubberHitLaneIsAtLeastFortyFourPoints() {
        XCTAssertGreaterThanOrEqual(PlayerSeekGeometry.hitLaneHeight, 44)
    }
}
