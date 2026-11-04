import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Drivy

/// Préparation locale d'un média (#97, T2b6) : type réel lu par le parseur système, octets
/// conservés, bornes du produit, miniature bornée produite en mémoire.
///
/// Écrits **avant** l'implémentation. Aucun outil Apple sur ce poste (Windows, ni Swift ni
/// Xcode) : le RED puis le GREEN restent à exécuter sur un runner Apple et ne sont pas
/// revendiqués par ce lot. Toutes les entrées sont synthétiques et générées ici, sans
/// fichier personnel, sans réseau et sans écriture disque du code testé.
final class MessagingMediaPreparationTests: XCTestCase {
    private let preparer = MessagingMediaPreparer()

    // MARK: - Fabriques synthétiques

    /// Échec de fabrique (jamais une erreur du code testé) : la fixture n'a pas pu être produite.
    private struct SyntheticFixtureError: Error {}

    /// Générateur congruentiel déterministe : bruit reproductible, aucune donnée réelle.
    private struct Noise {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 56)
        }
    }

    private func imageBytes(_ type: UTType, width: Int, height: Int, alpha: Bool,
                            noisy: Bool = false, orientation: Int? = nil,
                            gps: Bool = false, seed: UInt64 = 0x5EED_0097) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        var noise = Noise(seed: seed)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if noisy {
                pixels[index] = noise.next()
                pixels[index + 1] = noise.next()
                pixels[index + 2] = noise.next()
                pixels[index + 3] = alpha ? noise.next() : 255
            } else {
                pixels[index] = 32
                pixels[index + 1] = 64
                pixels[index + 2] = 96
                pixels[index + 3] = alpha ? 128 : 255
            }
        }
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 0.0,
                kCGImagePropertyGPSLongitude: 0.0
            ]
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: "SyntheticCamera"
            ]
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifUserComment: "synthetic"
            ]
        }
        return try encodeImage(pixels: pixels, width: width, height: height, type: type,
                               properties: properties)
    }

    private func encodeImage(pixels: [UInt8], width: Int, height: Int, type: UTType,
                             properties: [CFString: Any]) throws -> Data {
        var buffer = pixels
        let image: CGImage = try buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = context.makeImage() else {
                throw SyntheticFixtureError()
            }
            return image
        }
        return try encode(image, type: type, properties: properties)
    }

    private func encode(_ image: CGImage, type: UTType,
                        properties: [CFString: Any] = [:]) throws -> Data {
        guard let buffer = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(buffer, type.identifier as CFString, 1, nil) else {
            throw SyntheticFixtureError()
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw SyntheticFixtureError() }
        guard let bytes = CFDataGetBytePtr(buffer) else { throw SyntheticFixtureError() }
        return Data(bytes: bytes, count: CFDataGetLength(buffer))
    }

    /// PNG monochrome 1 bit dont le flux zlib est en blocs « stored » : fichier valide et
    /// complet de très grandes dimensions, sans jamais allouer ni encoder un bitmap RGBA
    /// de plusieurs centaines de mégaoctets pour le test.
    private func monochromePNG(width: Int, height: Int) throws -> Data {
        guard width >= 1, height >= 1 else { throw SyntheticFixtureError() }
        let rowBytes = (width + 7) / 8
        var raw = [UInt8]()
        raw.reserveCapacity((rowBytes + 1) * height)
        for _ in 0..<height {
            raw.append(0)
            raw.append(contentsOf: [UInt8](repeating: 0, count: rowBytes))
        }
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data(bigEndian(UInt32(width)))
        header.append(contentsOf: bigEndian(UInt32(height)))
        header.append(contentsOf: [1, 0, 0, 0, 0])
        png.append(chunk("IHDR", header))
        png.append(chunk("IDAT", deflateStored(raw)))
        png.append(chunk("IEND", Data()))
        return png
    }

    private func deflateStored(_ raw: [UInt8]) -> Data {
        var stream = Data([0x78, 0x01])
        var offset = 0
        repeat {
            let length = min(65_535, raw.count - offset)
            let isFinal: UInt8 = offset + length >= raw.count ? 1 : 0
            stream.append(isFinal)
            stream.append(UInt8(length & 0xFF))
            stream.append(UInt8((length >> 8) & 0xFF))
            let complement = UInt16(~UInt16(length))
            stream.append(UInt8(complement & 0xFF))
            stream.append(UInt8((complement >> 8) & 0xFF))
            stream.append(contentsOf: raw[offset..<(offset + length)])
            offset += length
        } while offset < raw.count
        stream.append(contentsOf: bigEndian(adler32(raw)))
        return stream
    }

    private func adler32(_ bytes: [UInt8]) -> UInt32 {
        var low: UInt32 = 1
        var high: UInt32 = 0
        for byte in bytes {
            low = (low + UInt32(byte)) % 65_521
            high = (high + low) % 65_521
        }
        return (high << 16) | low
    }

    private func chunk(_ type: String, _ payload: Data) -> Data {
        let typeBytes = Array(type.utf8)
        var out = Data(bigEndian(UInt32(payload.count)))
        out.append(contentsOf: typeBytes)
        out.append(payload)
        out.append(contentsOf: bigEndian(crc32(typeBytes + Array(payload))))
        return out
    }

    private func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// PDF minimal déterministe : catalogue, arbre de pages, une page et son flux de contenu.
    /// La même structure a été relue par un parseur PDF hors de ce dépôt ; PDFKit reste la
    /// preuve attendue côté Apple.
    private func pdfBytes(pageCount: Int) -> Data {
        var parts: [Data] = []
        var offsets: [Int: Int] = [:]
        func text(_ value: String) -> Data { Data(value.utf8) }
        func total() -> Int { parts.reduce(0) { $0 + $1.count } }
        func emit(_ number: Int, _ body: Data) {
            offsets[number] = total()
            parts.append(text("\(number) 0 obj\n") + body + text("\nendobj\n"))
        }

        let content = text("0 0 200 200 re S\n")
        parts.append(text("%PDF-1.7\n"))
        emit(1, text("<< /Type /Catalog /Pages 2 0 R >>"))
        let kids = (0..<pageCount).map { "\(3 + $0) 0 R" }.joined(separator: " ")
        emit(2, text("<< /Type /Pages /Kids [\(kids)] /Count \(pageCount) >>"))
        for index in 0..<pageCount {
            emit(3 + index,
                 text("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents \(3 + pageCount + index) 0 R >>"))
        }
        for index in 0..<pageCount {
            emit(3 + pageCount + index,
                 text("<< /Length \(content.count) >>\nstream\n") + content + text("endstream"))
        }
        let objectCount = 2 + 2 * pageCount
        let xrefOffset = total()
        var xref = text("xref\n0 \(objectCount + 1)\n0000000000 65535 f \n")
        for number in 1...objectCount {
            let digits = String(offsets[number] ?? 0)
            xref += text(String(repeating: "0", count: max(0, 10 - digits.count)) + digits + " 00000 n \n")
        }
        parts.append(xref)
        parts.append(text("trailer\n<< /Size \(objectCount + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"))
        return parts.reduce(Data()) { $0 + $1 }
    }

    /// PDF chiffré synthétique (AES-128, mot de passe utilisateur non vide) : produit hors de
    /// ce dépôt par une bibliothèque PDF, aucune donnée personnelle, aucun secret réel.
    private let passwordProtectedPDFBase64 = """
        JVBERi0xLjMKJeLjz9MKMSAwIG9iago8PAovUHJvZHVjZXIgPDczZjBjYmMzNDlkYzc5ZTllN2RjMDRjNDgwNDk5Mjg4YmFk
        ZWZjMGFkOTlmODdmNzhkZTkwNDdlOTJmYjNjODE+Cj4+CmVuZG9iagoyIDAgb2JqCjw8Ci9UeXBlIC9QYWdlcwovQ291bnQg
        MQovS2lkcyBbIDQgMCBSIF0KPj4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL0NhdGFsb2cKL1BhZ2VzIDIgMCBSCj4+CmVu
        ZG9iago0IDAgb2JqCjw8Ci9UeXBlIC9QYWdlCi9SZXNvdXJjZXMgPDwKPj4KL01lZGlhQm94IFsgMC4wIDAuMCAyMDAgMjAw
        IF0KL1BhcmVudCAyIDAgUgo+PgplbmRvYmoKNSAwIG9iago8PAovViA0Ci9SIDQKL0xlbmd0aCAxMjgKL1AgNDI5NDk2NzI5
        MgovRmlsdGVyIC9TdGFuZGFyZAovTyA8ZDAwOWIzMjZjZjNmYzk4ZmRlMWE5YjVmYWU4MzRhYjA3NDk4OWQwOTRjOTRhZTQx
        OWJkNmIzM2Q0MTBkZmY1Yj4KL1UgPGU4NjMzYmZlN2M0MTZmMzM0ODc3NzgwZThkOWExOTIyMjhiZjRlNWU0ZTc1OGE0MTY0
        MDA0ZTU2ZmZmYTAxMDg+Ci9DRiA8PAovU3RkQ0YgPDwKL0F1dGhFdmVudCAvRG9jT3BlbgovQ0ZNIC9BRVNWMgovTGVuZ3Ro
        IDE2Cj4+Cj4+Ci9TdG1GIC9TdGRDRgovU3RyRiAvU3RkQ0YKPj4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUg
        ZiAKMDAwMDAwMDAxNSAwMDAwMCBuIAowMDAwMDAwMTEzIDAwMDAwIG4gCjAwMDAwMDAxNzIgMDAwMDAgbiAKMDAwMDAwMDIy
        MSAwMDAwMCBuIAowMDAwMDAwMzE1IDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNgovUm9vdCAzIDAgUgovSW5mbyAxIDAg
        UgovSUQgWyA8MzUzOTYzMzIzMDYyNjI2MTY1NjMzODMyNjUzMTYyMzU2MzM2MzM2MzYxNjI2NTY2MzU2MTY2NjE2NTY2MzEz
        MT4gPDM1Mzk2MzMyMzA2MjYyNjE2NTYzMzgzMjY1MzE2MjM1NjMzNjMzNjM2MTYyNjU2NjM1NjE2NjYxNjU2NjMxMzE+IF0K
        L0VuY3J5cHQgNSAwIFIKPj4Kc3RhcnR4cmVmCjYyMgolJUVPRgo=
        """

    private func passwordProtectedPDF() throws -> Data {
        try XCTUnwrap(Data(base64Encoded: passwordProtectedPDFBase64,
                           options: .ignoreUnknownCharacters))
    }

    // MARK: - Utilitaires d'observation

    private func sourceProperties(_ data: Data) -> NSDictionary? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else { return nil }
        return properties as NSDictionary
    }

    private func imageSize(_ data: Data) throws -> (width: Int, height: Int) {
        let properties = try XCTUnwrap(sourceProperties(data))
        let width = try XCTUnwrap((properties.object(forKey: kCGImagePropertyPixelWidth) as? NSNumber)?.intValue)
        let height = try XCTUnwrap((properties.object(forKey: kCGImagePropertyPixelHeight) as? NSNumber)?.intValue)
        return (width, height)
    }

    private func imageType(_ data: Data) throws -> String {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(source))
        return type as String
    }

    private func assertFailure(_ expected: MessagingMediaPreparationFailure,
                               file: StaticString = #filePath, line: UInt = #line,
                               _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? MessagingMediaPreparationFailure, expected, file: file, line: line)
        }
    }

    // MARK: - Type réel, taille et nom

    func testJPEGIsPreparedWithItsRealTypeAndDisplaySize() throws {
        let original = try imageBytes(.jpeg, width: 640, height: 480, alpha: false)

        let prepared = try preparer.prepare(original, suggestedName: "IMG_0421.jpg")

        XCTAssertEqual(prepared.mime, .jpeg)
        XCTAssertEqual(prepared.name, "IMG_0421.jpg")
        XCTAssertEqual(prepared.width, 640)
        XCTAssertEqual(prepared.height, 480)
        XCTAssertEqual(prepared.data, original)
        let thumbnail = try XCTUnwrap(prepared.thumbnail)
        XCTAssertEqual(try imageType(thumbnail), UTType.jpeg.identifier)
        XCTAssertEqual(try imageSize(thumbnail).width, 512)
        XCTAssertEqual(try imageSize(thumbnail).height, 384)
    }

    func testPNGWithTransparencyIsPreparedAsPNG() throws {
        let original = try imageBytes(.png, width: 300, height: 200, alpha: true)

        let prepared = try preparer.prepare(original, suggestedName: "plan.png")

        XCTAssertEqual(prepared.mime, .png)
        XCTAssertEqual(prepared.width, 300)
        XCTAssertEqual(prepared.height, 200)
        XCTAssertEqual(prepared.data, original)
        let thumbnail = try XCTUnwrap(prepared.thumbnail)
        XCTAssertEqual(try imageType(thumbnail), UTType.png.identifier)
        let properties = try XCTUnwrap(sourceProperties(thumbnail))
        XCTAssertEqual((properties.object(forKey: kCGImagePropertyHasAlpha) as? NSNumber)?.boolValue, true)
    }

    func testDeclaredNameNeverDecidesTheType() throws {
        let pdf = pdfBytes(pageCount: 1)
        let jpeg = try imageBytes(.jpeg, width: 64, height: 64, alpha: false)

        XCTAssertEqual(try preparer.prepare(pdf, suggestedName: "photo.jpg").mime, .pdf)
        XCTAssertEqual(try preparer.prepare(jpeg, suggestedName: "bilan.pdf").mime, .jpeg)
    }

    func testSizeBoundIsCheckedBeforeAnyParser() throws {
        assertFailure(.invalidSize) {
            _ = try preparer.prepare(Data(), suggestedName: "photo.jpg")
        }
        let tooLarge = Data(repeating: 0xFF, count: MessagingMediaAttachment.maximumByteSize + 1)
        assertFailure(.invalidSize) {
            _ = try preparer.prepare(tooLarge, suggestedName: "photo.jpg")
        }
        // Exactement au plafond : la borne de taille est franchie, c'est le type qui refuse.
        let atCeiling = Data(repeating: 0xFF, count: MessagingMediaAttachment.maximumByteSize)
        assertFailure(.invalidFormat) {
            _ = try preparer.prepare(atCeiling, suggestedName: "photo.jpg")
        }
    }

    func testNameIsSanitisedAndBounded() throws {
        let jpeg = try imageBytes(.jpeg, width: 32, height: 32, alpha: false)

        let disguised = try preparer.prepare(jpeg, suggestedName: "photo\u{202E}gpj\u{0000}.jpg")
        XCTAssertEqual(disguised.name, "photogpj.jpg")

        let long = try preparer.prepare(jpeg, suggestedName: String(repeating: "a", count: 400))
        XCTAssertEqual(long.name.count, MessagingMediaAttachment.maximumNameLength)
    }

    func testUnusableNameIsRefused() throws {
        let jpeg = try imageBytes(.jpeg, width: 32, height: 32, alpha: false)

        assertFailure(.invalidName) {
            _ = try preparer.prepare(jpeg, suggestedName: "")
        }
        assertFailure(.invalidName) {
            _ = try preparer.prepare(jpeg, suggestedName: "\u{0000}\u{202A}  ")
        }
    }

    // MARK: - Parseur d'image

    func testTruncatedJPEGIsRefused() throws {
        let jpeg = try imageBytes(.jpeg, width: 800, height: 600, alpha: false, noisy: true)

        assertFailure(.unreadable) {
            _ = try preparer.prepare(jpeg.prefix(jpeg.count / 2), suggestedName: "photo.jpg")
        }
    }

    func testTruncatedPNGIsRefused() throws {
        let png = try imageBytes(.png, width: 800, height: 600, alpha: false, noisy: true)

        assertFailure(.unreadable) {
            _ = try preparer.prepare(png.prefix(png.count / 2), suggestedName: "plan.png")
        }
    }

    func testEmptyImageBodyIsRefused() throws {
        // Signature PNG seule : ni dimensions ni pixels exploitables.
        let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertThrowsError(try preparer.prepare(signature, suggestedName: "plan.png")) { error in
            // Deux catégories fermées de refus avant tout décodage ; le succès est interdit.
            switch error as? MessagingMediaPreparationFailure {
            case .unreadable, .invalidDimensions:
                break
            default:
                XCTFail("refus attendu avant tout décodage")
            }
        }
    }

    func testUnknownBytesAndForeignFormatsAreRefused() throws {
        var noise = Noise(seed: 0xBAD_C0DE)
        let random = Data((0..<4_096).map { _ in noise.next() })
        assertFailure(.invalidFormat) {
            _ = try preparer.prepare(random, suggestedName: "photo.jpg")
        }
        assertFailure(.invalidFormat) {
            _ = try preparer.prepare(Data("GIF89a".utf8) + random, suggestedName: "anim.gif")
        }
        assertFailure(.invalidFormat) {
            _ = try preparer.prepare(Data([0x00, 0x00, 0x00, 0x18]) + Data("ftypheic".utf8) + random,
                                     suggestedName: "photo.heic")
        }
        assertFailure(.invalidFormat) {
            _ = try preparer.prepare(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8),
                                     suggestedName: "dessin.svg")
        }
        assertFailure(.invalidFormat) {
            _ = try preparer.prepare(Data("not an image at all, not a pdf either".utf8),
                                     suggestedName: "fichier.bin")
        }
    }

    /// Refus au-delà de 12 000 px par axe, sans jamais allouer un bitmap de cette taille.
    func testAxisLimitIsEnforcedWithoutAGiantBitmap() throws {
        let beyond = try imageBytes(.png, width: MessagingMediaAttachment.maximumPixelsPerAxis + 1, height: 1,
                                    alpha: false)

        assertFailure(.invalidDimensions) {
            _ = try preparer.prepare(beyond, suggestedName: "large.png")
        }
    }

    /// Refus au-delà de 40 millions de pixels, la largeur restant sous 12 000 px : l'en-tête
    /// porte les dimensions, aucun bitmap de 40 millions de pixels n'est créé pour le test.
    func testPixelCountLimitIsEnforcedWithoutAGiantBitmap() throws {
        let beyond = try monochromePNG(width: 12_000, height: 3_400)
        XCTAssertGreaterThan(12_000 * 3_400, MessagingMediaAttachment.maximumPixels)

        assertFailure(.invalidDimensions) {
            _ = try preparer.prepare(beyond, suggestedName: "large.png")
        }
    }

    /// La borne est inclusive : 12 000 px sur un axe sont acceptés.
    func testAxisBoundaryIsAccepted() throws {
        let atLimit = try imageBytes(.png, width: MessagingMediaAttachment.maximumPixelsPerAxis, height: 1,
                                     alpha: false)

        let prepared = try preparer.prepare(atLimit, suggestedName: "bandeau.png")

        XCTAssertEqual(prepared.mime, .png)
        XCTAssertEqual(prepared.width, MessagingMediaAttachment.maximumPixelsPerAxis)
        XCTAssertEqual(prepared.height, 1)
        XCTAssertNotNil(prepared.thumbnail)
    }

    // MARK: - Miniature locale

    func testThumbnailIsBoundedInSizeAndKeepsTheAspect() throws {
        let jpeg = try imageBytes(.jpeg, width: 900, height: 300, alpha: false)

        let thumbnail = try XCTUnwrap(try preparer.prepare(jpeg, suggestedName: "panorama.jpg").thumbnail)

        XCTAssertLessThanOrEqual(thumbnail.count, MessagingMediaPreparer.maximumThumbnailByteSize)
        let size = try imageSize(thumbnail)
        XCTAssertEqual(size.width, MessagingMediaPreparer.maximumThumbnailAxis)
        XCTAssertLessThanOrEqual(abs(Double(size.height) - 300.0 * 512.0 / 900.0), 1.0)
    }

    /// Une orientation de rendu à 90° décale les dimensions : la miniature doit suivre l'affichage.
    func testThumbnailFollowsTheDisplayOrientation() throws {
        let rotated = try imageBytes(.jpeg, width: 900, height: 300, alpha: false, orientation: 6)
        let source = try XCTUnwrap(sourceProperties(rotated))
        XCTAssertEqual((source.object(forKey: kCGImagePropertyOrientation) as? NSNumber)?.intValue, 6,
                       "la fixture doit réellement porter l'orientation")

        let prepared = try preparer.prepare(rotated, suggestedName: "portrait.jpg")

        XCTAssertEqual(prepared.width, 300)
        XCTAssertEqual(prepared.height, 900)
        let size = try imageSize(try XCTUnwrap(prepared.thumbnail))
        XCTAssertEqual(size.height, MessagingMediaPreparer.maximumThumbnailAxis)
        XCTAssertLessThanOrEqual(abs(Double(size.width) - 300.0 * 512.0 / 900.0), 1.0)
    }

    func testNoisyOpaqueJPEGThumbnailStaysWithinTheBounds() throws {
        let noisy = try imageBytes(.jpeg, width: 2_400, height: 1_800, alpha: false, noisy: true)

        let thumbnail = try XCTUnwrap(try preparer.prepare(noisy, suggestedName: "bruit.jpg").thumbnail)

        XCTAssertLessThanOrEqual(thumbnail.count, MessagingMediaPreparer.maximumThumbnailByteSize)
        let size = try imageSize(thumbnail)
        XCTAssertLessThanOrEqual(max(size.width, size.height), MessagingMediaPreparer.maximumThumbnailAxis)
    }

    func testNoisyTransparentPNGThumbnailStaysWithinTheBounds() throws {
        let noisy = try imageBytes(.png, width: 1_024, height: 1_024, alpha: true, noisy: true)

        let thumbnail = try XCTUnwrap(try preparer.prepare(noisy, suggestedName: "bruit.png").thumbnail)

        XCTAssertLessThanOrEqual(thumbnail.count, MessagingMediaPreparer.maximumThumbnailByteSize)
        XCTAssertEqual(try imageType(thumbnail), UTType.png.identifier)
        let properties = try XCTUnwrap(sourceProperties(thumbnail))
        XCTAssertEqual((properties.object(forKey: kCGImagePropertyHasAlpha) as? NSNumber)?.boolValue, true)
        let size = try imageSize(thumbnail)
        XCTAssertLessThanOrEqual(max(size.width, size.height), MessagingMediaPreparer.maximumThumbnailAxis)
    }

    /// La miniature est reconstruite depuis les pixels : aucune métadonnée personnelle recopiée.
    func testThumbnailCarriesNoPersonalMetadataFromTheOriginal() throws {
        let withMetadata = try imageBytes(.jpeg, width: 800, height: 600, alpha: false, gps: true)
        let original = try XCTUnwrap(sourceProperties(withMetadata))
        XCTAssertNotNil(original.object(forKey: kCGImagePropertyGPSDictionary),
                        "la fixture doit réellement porter des métadonnées")

        let thumbnail = try XCTUnwrap(try preparer.prepare(withMetadata, suggestedName: "lieu.jpg").thumbnail)
        let properties = try XCTUnwrap(sourceProperties(thumbnail))

        XCTAssertNil(properties.object(forKey: kCGImagePropertyGPSDictionary))
        XCTAssertNil(properties.object(forKey: kCGImagePropertyExifDictionary))
        XCTAssertNil(properties.object(forKey: kCGImagePropertyTIFFDictionary))
    }

    func testThumbnailIsNeverTheOriginalBytes() throws {
        let original = try imageBytes(.jpeg, width: 640, height: 480, alpha: false)

        let prepared = try preparer.prepare(original, suggestedName: "photo.jpg")

        XCTAssertNotEqual(prepared.thumbnail, prepared.data)
    }

    // MARK: - PDF en mémoire

    func testPDFIsPreparedFromMemoryWithNoDimensionsAndNoThumbnail() throws {
        let pdf = pdfBytes(pageCount: 1)

        let prepared = try preparer.prepare(pdf, suggestedName: "bilan.pdf")

        XCTAssertEqual(prepared.mime, .pdf)
        XCTAssertEqual(prepared.name, "bilan.pdf")
        XCTAssertNil(prepared.width)
        XCTAssertNil(prepared.height)
        XCTAssertNil(prepared.thumbnail)
        XCTAssertEqual(prepared.data, pdf)
    }

    func testEmptyPDFIsRefused() throws {
        let empty = pdfBytes(pageCount: 0)

        assertFailure(.unreadable) {
            _ = try preparer.prepare(empty, suggestedName: "vide.pdf")
        }
    }

    func testCorruptedPDFIsRefused() throws {
        let corrupted = Data("%PDF-1.7\n1 0 obj\n<< /Type /Catalog\n".utf8)

        assertFailure(.unreadable) {
            _ = try preparer.prepare(corrupted, suggestedName: "corrompu.pdf")
        }
    }

    func testPasswordProtectedPDFIsRefusedWithoutPasswordPrompt() throws {
        let locked = try passwordProtectedPDF()

        assertFailure(.lockedPDF) {
            _ = try preparer.prepare(locked, suggestedName: "verrouille.pdf")
        }
    }

    // MARK: - Invariants du lot

    func testOriginalBytesAreNeverModified() throws {
        let jpeg = try imageBytes(.jpeg, width: 320, height: 240, alpha: false)
        let png = try imageBytes(.png, width: 320, height: 240, alpha: true)
        let pdf = pdfBytes(pageCount: 1)

        for (bytes, name) in [(jpeg, "photo.jpg"), (png, "plan.png"), (pdf, "bilan.pdf")] {
            var copy = bytes
            _ = try preparer.prepare(bytes, suggestedName: name)
            XCTAssertEqual(copy, bytes)
            copy.append(0x00)
            XCTAssertNotEqual(copy, bytes)
        }
    }

    /// Vérification faible (répertoire temporaire du processus seulement) : la garantie forte
    /// est structurelle — aucune API d'URL, de chemin ou de fichier dans la préparation.
    func testPreparationDoesNotWriteToTheTemporaryDirectory() throws {
        let jpeg = try imageBytes(.jpeg, width: 480, height: 360, alpha: false)
        let directory = FileManager.default.temporaryDirectory
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))

        _ = try preparer.prepare(jpeg, suggestedName: "photo.jpg")

        let after = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(before, after)
    }

    /// Le protocole est le seul point d'entrée : des octets et un nom, jamais une URL ni un chemin.
    func testProtocolSeamTakesBytesAndAName() throws {
        let seam: any MessagingMediaPreparing = MessagingMediaPreparer()
        let jpeg = try imageBytes(.jpeg, width: 96, height: 96, alpha: false)

        let prepared = try seam.prepare(jpeg, suggestedName: "photo.jpg")

        XCTAssertEqual(prepared, try preparer.prepare(jpeg, suggestedName: "photo.jpg"))
    }
}
