import UIKit
import XCTest
@testable import Drivy

/// Cadrage de la photo de profil (#156) : le carré vu dans le cadre est celui qui part, l’image couvre toujours le cadre.
final class SchoolProfilePhotoCropTests: XCTestCase {
    private let landscape = CGSize(width: 2000, height: 1000)

    func testZoomOneFillsTheFrameWithTheShortSideAndCentersTheSquare() {
        let rect = SchoolProfilePhotoEncoder.cropRect(imageSize: landscape, frameSide: 300, zoom: 1, offset: .zero)
        XCTAssertEqual(rect.width, 1000, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1000, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 1000, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 500, accuracy: 0.001)
    }

    func testDraggingTheImageRightShowsItsLeftPart() {
        let centered = SchoolProfilePhotoEncoder.cropRect(imageSize: landscape, frameSide: 300, zoom: 1, offset: .zero)
        let moved = SchoolProfilePhotoEncoder.cropRect(imageSize: landscape, frameSide: 300, zoom: 1,
                                                       offset: CGSize(width: 60, height: 0))
        XCTAssertLessThan(moved.minX, centered.minX)
        XCTAssertEqual(moved.minY, centered.minY, accuracy: 0.001)
    }

    func testOffsetNeverUncoversTheFrame() {
        // Au zoom 1, l’image paysage ne bouge pas verticalement et ne dépasse pas ses bords horizontalement.
        let clamped = SchoolProfilePhotoEncoder.clampedOffset(CGSize(width: 10_000, height: 10_000), imageSize: landscape,
                                                              frameSide: 300, zoom: 1)
        XCTAssertEqual(clamped.height, 0, accuracy: 0.001)
        XCTAssertEqual(clamped.width, 150, accuracy: 0.001)
        let rect = SchoolProfilePhotoEncoder.cropRect(imageSize: landscape, frameSide: 300, zoom: 1,
                                                      offset: CGSize(width: 10_000, height: 10_000))
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
    }

    func testZoomIsBoundedAndShrinksTheSquare() {
        let doubled = SchoolProfilePhotoEncoder.cropRect(imageSize: landscape, frameSide: 300, zoom: 2, offset: .zero)
        XCTAssertEqual(doubled.width, 500, accuracy: 0.001)
        let beyond = SchoolProfilePhotoEncoder.cropRect(imageSize: landscape, frameSide: 300, zoom: 40, offset: .zero)
        XCTAssertEqual(beyond.width, 1000 / SchoolProfilePhotoEncoder.maxZoom, accuracy: 0.001)
        let below = SchoolProfilePhotoEncoder.cropRect(imageSize: landscape, frameSide: 300, zoom: 0.2, offset: .zero)
        XCTAssertEqual(below.width, 1000, accuracy: 0.001)
    }

    func testPreviewIsReducedAndTheCroppedSquareIsASmallJPEG() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let original = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))
        let preview = try XCTUnwrap(SchoolProfilePhotoEncoder.uprightPreview(from: original))
        let reduced = try XCTUnwrap(UIImage(data: preview)?.cgImage)
        XCTAssertLessThanOrEqual(max(reduced.width, reduced.height), SchoolProfilePhotoEncoder.previewMaxPixel)

        let size = CGSize(width: reduced.width, height: reduced.height)
        let crop = SchoolProfilePhotoEncoder.cropRect(imageSize: size, frameSide: 300, zoom: 1.5, offset: CGSize(width: 40, height: -20))
        let jpeg = try XCTUnwrap(SchoolProfilePhotoEncoder.squareJPEG(fromPreview: preview, crop: crop))
        XCTAssertLessThanOrEqual(jpeg.count, SchoolProfilePhotoEncoder.maxBytes)
        let avatar = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
        XCTAssertEqual(avatar.width, avatar.height)
        XCTAssertLessThanOrEqual(CGFloat(avatar.width), SchoolProfilePhotoEncoder.side)
    }

    func testTooSmallACropIsRefused() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        XCTAssertNil(SchoolProfilePhotoEncoder.squareJPEG(fromPreview: data, crop: CGRect(x: 0, y: 0, width: 40, height: 40)))
    }
}
