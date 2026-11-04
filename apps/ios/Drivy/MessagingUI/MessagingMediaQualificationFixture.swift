#if DEBUG && targetEnvironment(simulator)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Synthetic bytes only, generated in memory. No file, identity, socket or persistence.
enum MessagingMediaQualificationSamples {
    private struct GenerationFailure: Error {}

    static func photo() throws -> MessagingImportedMedia {
        let width = 240, height = 160
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw GenerationFailure() }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 80, y: 40, width: 80, height: 80))
        guard let image = context.makeImage() else { throw GenerationFailure() }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)
        else { throw GenerationFailure() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationFailure() }
        return MessagingImportedMedia(data: bytes as Data, suggestedName: "Photo synthétique.png")
    }

    static func pdf() throws -> MessagingImportedMedia {
        let bytes = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 320, height: 440)
        guard let consumer = CGDataConsumer(data: bytes),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw GenerationFailure() }
        for page in 0..<2 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(x: 32, y: 330, width: 200, height: 20))
            context.fill(CGRect(x: 32, y: 280, width: CGFloat(100 + page * 60), height: 12))
            context.endPDFPage()
        }
        context.closePDF()
        return MessagingImportedMedia(data: bytes as Data, suggestedName: "Document synthétique.pdf")
    }
}
#endif
