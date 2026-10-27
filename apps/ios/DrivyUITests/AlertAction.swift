import XCTest

/// iOS 26 expose parfois Button > Button : le conteneur ne déclenche pas l'action lors du tap XCTest.
@MainActor func tapAlertAction(in app: XCUIApplication, identifier: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
    let matches = app.alerts.buttons.matching(identifier: identifier)
    XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    let leaves = matches.allElementsBoundByIndex.filter {
        $0.descendants(matching: .button).matching(identifier: identifier).count == 0
    }
    let action = try XCTUnwrap(leaves.count == 1 ? leaves[0] : nil,
                              "Une action terminale unique est attendue pour \(identifier)", file: file, line: line)
    XCTAssertTrue(action.isHittable, file: file, line: line)
    action.tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5), "Le dialogue doit se fermer", file: file, line: line)
}
