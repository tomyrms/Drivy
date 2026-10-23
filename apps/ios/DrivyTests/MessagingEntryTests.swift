import XCTest
import SwiftUI
@testable import Drivy

final class MessagingEntryTests: XCTestCase {
    @MainActor
    func testMessagingEntryIsAbsentUnlessExplicitlyComposed() {
        XCTAssertNil(EnvironmentValues().schoolMessagingEntry)
    }

    func testDevelopmentEntryRequiresExplicitFlagAndActiveSchool() {
        XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: [], schoolIsActive: true))
        XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: ["-messaging-ui-fixture"], schoolIsActive: true))
        XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: ["-messaging-development"], schoolIsActive: false))
        #if DEBUG && targetEnvironment(simulator)
        XCTAssertTrue(SchoolMessagingDevelopment.permitted(arguments: ["-messaging-development"], schoolIsActive: true))
        #else
        XCTAssertFalse(SchoolMessagingDevelopment.permitted(arguments: ["-messaging-development"], schoolIsActive: true))
        #endif
    }
}
