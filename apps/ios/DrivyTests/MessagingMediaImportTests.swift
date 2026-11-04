import Foundation
import XCTest
@testable import Drivy

/// Test-first. RED/GREEN non exécutés : environnement Windows sans SDK Apple.
final class MessagingMediaImportTests: XCTestCase {
    func testReadsOriginalBytesWithoutChangingThem() throws {
        let original = Data([0, 1, 2, 255])
        let stream = InputStream(data: original)
        XCTAssertEqual(try MessagingMediaImport.read(stream), original)
    }

    func testRejectsEmptyInput() {
        XCTAssertThrowsError(try MessagingMediaImport.read(InputStream(data: Data()))) {
            XCTAssertEqual($0 as? MessagingMediaImportFailure, .invalidSize)
        }
    }

    func testAcceptsExactlyFourMiB() throws {
        let original = Data(repeating: 17, count: 4_194_304)
        XCTAssertEqual(try MessagingMediaImport.read(InputStream(data: original)), original)
    }

    func testRejectsAnExtraByteEvenWithoutProviderSize() {
        let stream = InputStream(data: Data(repeating: 17, count: 4_194_305))
        XCTAssertThrowsError(try MessagingMediaImport.read(stream)) {
            XCTAssertEqual($0 as? MessagingMediaImportFailure, .invalidSize)
        }
    }

    func testCancellationStopsBeforeReading() {
        XCTAssertThrowsError(try MessagingMediaImport.read(InputStream(data: Data([1])), cancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testCancellationBetweenBlocksDoesNotReturnPartialFile() {
        var checks = 0
        let stream = InputStream(data: Data(repeating: 17, count: 131_072))
        XCTAssertThrowsError(try MessagingMediaImport.read(stream, cancelled: {
            checks += 1
            return checks > 1
        })) { XCTAssertTrue($0 is CancellationError) }
    }

    func testNonFileURLIsRefused() {
        XCTAssertThrowsError(try MessagingMediaImport.readFile(URL(string: "https://example.invalid/a.pdf")!)) {
            XCTAssertEqual($0 as? MessagingMediaImportFailure, .unreadable)
        }
    }
}
