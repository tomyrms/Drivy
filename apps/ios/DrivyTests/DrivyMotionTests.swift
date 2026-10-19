import XCTest
@testable import Drivy

final class DrivyMotionTests: XCTestCase {
    func testProgressIsImmediateWhenReduceMotionIsEnabled() {
        XCTAssertNil(DrivyMotion.progress(true, duration: 0.5))
        XCTAssertNil(DrivyMotion.progress(true, duration: 1.5))
    }

    func testProgressUsesCallerDurationWhenMotionIsEnabled() {
        XCTAssertEqual(DrivyMotion.progressDuration(false, duration: 0.5), 0.5)
        XCTAssertEqual(DrivyMotion.progressDuration(false, duration: 1.5), 1.5)
        XCTAssertNotNil(DrivyMotion.progress(false, duration: 1.5))
    }

    func testExistingFeedbackContractRemainsAvailable() {
        XCTAssertNil(DrivyMotion.feedback(true))
        XCTAssertNotNil(DrivyMotion.feedback(false))
    }
}
