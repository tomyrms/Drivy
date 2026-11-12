import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Drivy

/// Logique pure de la visionneuse (#474) : aucun UIKit, aucun geste réel.
final class MessagingMediaViewerTests: XCTestCase {
    private typealias Zoom = MessagingZoomGeometry

    func testFittedSizeKeepsProportionsInBothOrientations() {
        let landscape = Zoom.fittedSize(content: CGSize(width: 4000, height: 2000), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(landscape.width, 400, accuracy: 0.001)
        XCTAssertEqual(landscape.height, 200, accuracy: 0.001)
        let portrait = Zoom.fittedSize(content: CGSize(width: 1000, height: 3000), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(portrait.height, 800, accuracy: 0.001)
        XCTAssertEqual(portrait.width / portrait.height, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testFittedSizeIsEmptyForDegenerateInput() {
        XCTAssertEqual(Zoom.fittedSize(content: .zero, in: CGSize(width: 10, height: 10)), .zero)
        XCTAssertEqual(Zoom.fittedSize(content: CGSize(width: 10, height: 10), in: .zero), .zero)
    }

    func testMaximumScaleIsClampedBetweenThreeAndEight() {
        let fitted = CGSize(width: 300, height: 300)
        XCTAssertEqual(Zoom.maximumScale(pixelSize: CGSize(width: 300, height: 300), fitted: fitted, displayScale: 3), 3)
        XCTAssertEqual(Zoom.maximumScale(pixelSize: CGSize(width: 90_000, height: 90_000), fitted: fitted, displayScale: 3), 8)
        // 3000 px sur 300 pt à 3x : natif = 3,33 ; deux fois = 6,67.
        XCTAssertEqual(Zoom.maximumScale(pixelSize: CGSize(width: 3000, height: 3000), fitted: fitted, displayScale: 3), 20.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(Zoom.maximumScale(pixelSize: .zero, fitted: .zero, displayScale: 0), 3)
    }

    func testDoubleTapZoomsInThenReturnsToFit() {
        let fitted = CGSize(width: 390, height: 400)
        let viewport = CGSize(width: 390, height: 800)
        let first = Zoom.doubleTapTarget(current: 1, minimum: 1, maximum: 6, fitted: fitted, viewport: viewport)
        XCTAssertGreaterThan(first, 1)
        XCTAssertGreaterThanOrEqual(first, Zoom.doubleTapScale)
        // Remplit le cadre : 800 / 400 = 2 < 2,5, donc 2,5.
        XCTAssertEqual(first, 2.5, accuracy: 0.001)
        XCTAssertEqual(Zoom.doubleTapTarget(current: first, minimum: 1, maximum: 6, fitted: fitted, viewport: viewport), 1)
    }

    func testDoubleTapFillsFrameForTallScreenshotAndRespectsMaximum() {
        let fitted = CGSize(width: 100, height: 800)
        let viewport = CGSize(width: 400, height: 800)
        XCTAssertEqual(Zoom.doubleTapTarget(current: 1, minimum: 1, maximum: 8, fitted: fitted, viewport: viewport), 4, accuracy: 0.001)
        XCTAssertEqual(Zoom.doubleTapTarget(current: 1, minimum: 1, maximum: 3, fitted: fitted, viewport: viewport), 3, accuracy: 0.001)
    }

    func testSlightlyZoomedStateStillCountsAsFitted() {
        XCTAssertGreaterThan(Zoom.doubleTapTarget(current: 1.02, minimum: 1, maximum: 6,
                                                  fitted: CGSize(width: 390, height: 400), viewport: CGSize(width: 390, height: 800)), 1)
    }

    func testZoomRectIsCenteredOnTheTappedPoint() {
        let rect = Zoom.zoomRect(center: CGPoint(x: 200, y: 100), scale: 2, viewport: CGSize(width: 400, height: 800))
        XCTAssertEqual(rect.size, CGSize(width: 200, height: 400))
        XCTAssertEqual(rect.midX, 200, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 100, accuracy: 0.001)
    }

    func testZoomRectNeverExceedsTheViewportBelowScaleOne() {
        let rect = Zoom.zoomRect(center: .zero, scale: 0.2, viewport: CGSize(width: 400, height: 800))
        XCTAssertEqual(rect.size, CGSize(width: 400, height: 800))
    }

    func testSmallContentIsCenteredAndLargeContentIsNot() {
        let inset = Zoom.centeringInset(content: CGSize(width: 300, height: 900), bounds: CGSize(width: 400, height: 800))
        XCTAssertEqual(inset.width, 50, accuracy: 0.001)
        XCTAssertEqual(inset.height, 0)
    }

    func testOffsetIsClampedToThePanningBounds() {
        let content = CGSize(width: 1200, height: 1600), bounds = CGSize(width: 400, height: 800)
        XCTAssertEqual(Zoom.clampedOffset(CGPoint(x: -50, y: 5000), content: content, bounds: bounds), CGPoint(x: 0, y: 800))
        XCTAssertEqual(Zoom.clampedOffset(CGPoint(x: 300, y: 100), content: content, bounds: bounds), CGPoint(x: 300, y: 100))
    }

    func testOffsetOfSmallContentIsPinnedToItsCenteringInset() {
        let offset = Zoom.clampedOffset(CGPoint(x: 99, y: -99), content: CGSize(width: 300, height: 400), bounds: CGSize(width: 400, height: 800))
        XCTAssertEqual(offset, CGPoint(x: -50, y: -200))
    }

    func testDecodeSizeIsBoundedByScreenSourceAndCeiling() {
        // Écran 852 pt à 3x : 2556 px, deux fois = 5112, plafonné à 4096.
        XCTAssertEqual(Zoom.decodeMaxPixel(sourceLongestSide: 12_000, viewportLongestSide: 852, displayScale: 3), 4096)
        // Jamais plus que la source.
        XCTAssertEqual(Zoom.decodeMaxPixel(sourceLongestSide: 1000, viewportLongestSide: 852, displayScale: 3), 1000)
        // Petit cadre : deux fois ses pixels.
        XCTAssertEqual(Zoom.decodeMaxPixel(sourceLongestSide: 9000, viewportLongestSide: 500, displayScale: 2), 2000)
        // Plancher pour un cadre minuscule.
        XCTAssertEqual(Zoom.decodeMaxPixel(sourceLongestSide: 9000, viewportLongestSide: 10, displayScale: 1), 512)
        XCTAssertEqual(Zoom.decodeMaxPixel(sourceLongestSide: 0, viewportLongestSide: 500, displayScale: 2), 2000)
    }

    func testDecoderDownsamplesOnceAndKeepsAspectRatio() throws {
        let data = try Self.png(width: 3000, height: 1500)
        let decoded = try XCTUnwrap(MessagingImageDecoder.decode(data, viewportLongestSide: 300, displayScale: 1))
        XCTAssertEqual(decoded.pixelSize.width, 600, accuracy: 1)
        XCTAssertEqual(decoded.pixelSize.width / decoded.pixelSize.height, 2, accuracy: 0.01)
    }

    func testDecoderDoesNotUpscaleSmallImages() throws {
        let data = try Self.png(width: 200, height: 100)
        let decoded = try XCTUnwrap(MessagingImageDecoder.decode(data, viewportLongestSide: 800, displayScale: 3))
        XCTAssertEqual(decoded.pixelSize.width, 200, accuracy: 1)
    }

    func testDecoderRejectsBytesThatAreNotAnImage() {
        XCTAssertNil(MessagingImageDecoder.decode(Data([0x00, 0x01, 0x02]), viewportLongestSide: 800, displayScale: 3))
    }

    func testViewerStateEquality() {
        XCTAssertEqual(MessagingMediaViewerState.loading, .loading)
        XCTAssertNotEqual(MessagingMediaViewerState.failed("a"), .failed("b"))
    }

    private static func png(width: Int, height: Int) throws -> Data {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { throw XCTSkip("Contexte graphique indisponible") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw XCTSkip("Encodeur PNG indisponible")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("Encodage PNG impossible") }
        return output as Data
    }
}
