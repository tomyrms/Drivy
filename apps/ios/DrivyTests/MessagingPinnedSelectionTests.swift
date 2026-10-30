import XCTest
@testable import Drivy

final class MessagingPinnedSelectionTests: XCTestCase {
    func testReadingTheCurrentPinDoesNotAdvanceIt() {
        let first = UUID(), second = UUID()
        var selection = MessagingPinnedSelection()
        selection.reconcile(with: [first, second])
        XCTAssertEqual(selection.current(in: [first, second]), first)
        XCTAssertEqual(selection.current(in: [first, second]), first)
        selection.advance(in: [first, second])
        XCTAssertEqual(selection.current(in: [first, second]), second)
        selection.advance(in: [first, second])
        XCTAssertEqual(selection.current(in: [first, second]), first)
    }

    func testLoadingOlderPinsAndRemovingAnotherPinPreserveTheSelectedIdentity() {
        let older = UUID(), first = UUID(), selected = UUID()
        var selection = MessagingPinnedSelection()
        selection.reconcile(with: [first, selected])
        selection.advance(in: [first, selected])
        selection.reconcile(with: [older, first, selected])
        XCTAssertEqual(selection.current(in: [older, first, selected]), selected)
        selection.reconcile(with: [older, selected])
        XCTAssertEqual(selection.current(in: [older, selected]), selected)
        selection.advance(in: [older, selected], backwards: true)
        XCTAssertEqual(selection.current(in: [older, selected]), older)
    }

    func testRemovedTargetAndEmptyListNeverKeepAnUnavailablePin() {
        let first = UUID(), removed = UUID(), replacement = UUID()
        var selection = MessagingPinnedSelection()
        selection.reconcile(with: [first, removed])
        selection.advance(in: [first, removed])
        selection.reconcile(with: [first, replacement])
        XCTAssertEqual(selection.current(in: [first, replacement]), first)
        selection.reconcile(with: [])
        XCTAssertNil(selection.current(in: []))
        selection.advance(in: [])
        XCTAssertNil(selection.selectedID)
        selection.reconcile(with: [replacement, first])
        XCTAssertEqual(selection.current(in: [replacement, first]), replacement)
    }
}
