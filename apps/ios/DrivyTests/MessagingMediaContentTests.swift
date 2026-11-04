import XCTest
@testable import Drivy

/// Contenu v3 média (#97, T2b1) : forme exacte du contrat §4.2, bornes locales et échecs fermés.
/// Écrits, non exécutés ici : aucun outil Apple sur ce poste, la preuve vient d'un runner Apple.
final class MessagingMediaContentTests: XCTestCase {
    private let mediaID = UUID(uuidString: "5c1f0000-0000-4000-8000-000000000001")!

    /// Métadonnées crypto synthétiques et canoniques : ni clé, ni IV réels.
    private func fileInfo() -> MessagingMediaEncryptionInfo {
        MessagingMediaEncryptionInfo(key: Data(repeating: 7, count: 32),
                                     iv: Data(repeating: 0, count: 16),
                                     sha256: Data(repeating: 9, count: 32))
    }

    private func attachment(_ mime: MessagingMediaAttachment.MIME = .jpeg,
                            name: String = "IMG_0421.jpg",
                            size: Int = 1_834_021,
                            width: Int? = 2_048,
                            height: Int? = 1_536) throws -> MessagingMediaAttachment {
        try MessagingMediaAttachment(id: mediaID, size: size, mime: mime, name: name,
                                     width: width, height: height, file: fileInfo())
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Forme exacte du contenu v3

    func testMediaContentUsesTheNamespacedShapeWithAReadableBody() throws {
        let content = MessagingPlainContent(text: "Légende de la photo", media: try attachment())
        let data = try content.encoded()
        let contentObject = try object(data)
        XCTAssertEqual(Set(contentObject.keys), Set(["msgtype", "body", "ch.drivy.messaging"]))
        XCTAssertEqual(contentObject["msgtype"] as? String, "m.text")
        XCTAssertEqual(contentObject["body"] as? String, "Légende de la photo",
                       "Le body porte la légende, jamais le JSON v3")
        let namespaced = try XCTUnwrap(contentObject["ch.drivy.messaging"] as? [String: Any])
        XCTAssertEqual(namespaced["v"] as? Int, 3)
        XCTAssertEqual(namespaced["text"] as? String, "Légende de la photo")
        let media = try XCTUnwrap(namespaced["media"] as? [String: Any])
        XCTAssertEqual(Set(media.keys), Set(["id", "size", "mime", "name", "width", "height", "file"]),
                       "Champs exacts du §4.2, aucune ressource externe ni miniature")
        XCTAssertEqual(media["id"] as? String, mediaID.uuidString)
        XCTAssertEqual(media["size"] as? Int, 1_834_021)
        XCTAssertEqual(media["mime"] as? String, "image/jpeg")
        XCTAssertEqual(media["name"] as? String, "IMG_0421.jpg")
        XCTAssertEqual(media["width"] as? Int, 2_048)
        XCTAssertEqual(media["height"] as? Int, 1_536)
        let file = try XCTUnwrap(media["file"] as? [String: Any])
        XCTAssertEqual(Set(file.keys), Set(["v", "key", "iv", "hashes"]))
        XCTAssertEqual(file["v"] as? String, "v2")
        // Aucune ressource externe : la forme exacte du §4.2 ne porte ni URL, ni chemin, ni miniature.
        for forbidden in ["url", "downloadUrl", "path", "thumbnail", "preview"] {
            XCTAssertNil(media[forbidden], forbidden)
        }
    }

    func testBodyFallsBackToTheMimeWhenThereIsNoCaption() throws {
        XCTAssertEqual(try MessagingPlainContent(text: nil, media: try attachment(.jpeg)).encoded().bodyText, "Photo")
        XCTAssertEqual(try MessagingPlainContent(text: "   ", media: try attachment(.png, name: "capture.png", width: 800, height: 600)).encoded().bodyText, "Photo")
        XCTAssertEqual(try MessagingPlainContent(text: nil, media: try attachment(.pdf, name: "bilan.pdf", width: nil, height: nil)).encoded().bodyText, "PDF")
    }

    func testSummaryStaysReadableForAMediaMessage() throws {
        XCTAssertEqual(MessagingPlainContent(text: "Légende", media: try attachment()).summary, "Légende")
        XCTAssertEqual(MessagingPlainContent(media: try attachment(.png, name: "capture.png", width: 10, height: 10)).summary, "Photo")
        XCTAssertEqual(MessagingPlainContent(media: try attachment(.pdf, name: "bilan.pdf", width: nil, height: nil)).summary, "PDF")
    }

    func testMediaContentRoundTripsThroughItsOwnEncoding() throws {
        let content = MessagingPlainContent(text: "Légende", media: try attachment())
        let decoded = try XCTUnwrap(MessagingPlainContent.decode(try content.encoded()))
        XCTAssertEqual(decoded, content)
        XCTAssertEqual(decoded.media?.name, "IMG_0421.jpg")
        XCTAssertEqual(decoded.media?.mime, .jpeg)
        XCTAssertEqual(decoded.media?.file, fileInfo())
    }

    /// L'encodage d'un message sans média ne bouge pas : les intentions déjà scellées gardent leurs octets.
    func testContentWithoutMediaKeepsTheVersionTwoEnvelope() throws {
        let poll = MessagingPlainContent(poll: .init(question: "Q", options: [.init(id: "o1", label: "A"), .init(id: "o2", label: "B")]))
        let data = try poll.encoded()
        let envelope = try object(data)
        XCTAssertEqual(Set(envelope.keys), Set(["v", "text", "poll"]))
        XCTAssertEqual(envelope["v"] as? Int, 2)
        XCTAssertNil(envelope["ch.drivy.messaging"])
    }

    // MARK: Bornes du contrat §4.2

    func testCaptionIsBoundedToThousandCharacters() throws {
        let atLimit = String(repeating: "a", count: 1_000)
        XCTAssertNoThrow(try MessagingMediaContentV3(text: atLimit, media: try attachment()))
        XCTAssertThrowsError(try MessagingMediaContentV3(text: atLimit + "a", media: try attachment())) { error in
            XCTAssertEqual(error as? MessagingFailure, .invalidResponse)
        }
    }

    /// La borne se mesure sur le contenu encodé, pas sur le nombre de caractères.
    func testEncodedContentIsBoundedToSixThousandBytes() throws {
        let ordinary = String(repeating: "a", count: 1_000)
        let heaviest = String(repeating: "a\u{0301}\u{0301}\u{0301}\u{0301}\u{0301}", count: 1_000)
        XCTAssertEqual(heaviest.count, 1_000, "Mille caractères, mais bien plus d'octets une fois encodé")
        XCTAssertLessThanOrEqual(try MessagingPlainContent(text: ordinary, media: try attachment(name: String(repeating: "é", count: 255))).encoded().count,
                                 MessagingPlainContent.maximumV3ByteCount)
        XCTAssertThrowsError(try MessagingPlainContent(text: heaviest, media: try attachment()).encoded()) { error in
            XCTAssertEqual(error as? MessagingFailure, .invalidResponse)
        }
    }

    func testMediaSizeIsBoundedToOneAndFourMebibytes() throws {
        XCTAssertThrowsError(try attachment(size: 0))
        XCTAssertNoThrow(try attachment(size: 1))
        XCTAssertNoThrow(try attachment(size: MessagingMediaAttachment.maximumByteSize))
        XCTAssertThrowsError(try attachment(size: MessagingMediaAttachment.maximumByteSize + 1))
        XCTAssertThrowsError(try attachment(size: -1))
    }

    func testMimeIsRestrictedToTheThreeContractTypes() throws {
        XCTAssertEqual(MessagingMediaAttachment.MIME.allCases.map(\.rawValue).sorted(),
                       ["application/pdf", "image/jpeg", "image/png"])
        let payload = Data(#"{"id":"\#(mediaID)","size":10,"mime":"image/gif","name":"a.gif","file":{"v":"v2","key":{"kty":"oct","alg":"A256CTR","ext":true,"k":"\#(String(repeating: "A", count: 43))","key_ops":["decrypt","encrypt"]},"iv":"\#(String(repeating: "A", count: 22))","hashes":{"sha256":"\#(String(repeating: "A", count: 43))"}}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MessagingMediaAttachment.self, from: payload))
    }

    func testNameIsSanitisedOfControlsAndBidiAndBoundedToTwoHundredFiftyFiveCharacters() throws {
        XCTAssertEqual(MessagingMediaName.sanitized("IMG_0421.jpg"), "IMG_0421.jpg")
        XCTAssertEqual(MessagingMediaName.sanitized("\u{0000}\u{0001}photo\u{007F}\u{0085}.jpg"), "photo.jpg")
        XCTAssertEqual(MessagingMediaName.sanitized("photo\u{202E}gnp.exe"), "photognp.exe",
                       "Les contrôles bidi ne restent pas dans un nom affiché")
        XCTAssertEqual(MessagingMediaName.sanitized("a\u{2066}b\u{2069}c"), "abc")
        XCTAssertEqual(MessagingMediaName.sanitized("../dossier/photo.jpg"), "..dossierphoto.jpg",
                       "Un nom n'est jamais un chemin")
        XCTAssertEqual(MessagingMediaName.sanitized("\\\\serveur\\partage\\photo.jpg"), "serveurpartagephoto.jpg")
        XCTAssertEqual(MessagingMediaName.sanitized(String(repeating: "a", count: 300))?.count, 255)
        XCTAssertNil(MessagingMediaName.sanitized("\u{0000}\u{202A}  "))
        XCTAssertThrowsError(try attachment(name: "\u{0000}\u{202E}")) { error in
            XCTAssertEqual(error as? MessagingFailure, .invalidResponse)
        }
        // Un nom trop long est borné, jamais refusé en silence puis transmis tel quel.
        XCTAssertEqual(try attachment(name: String(repeating: "b", count: 400)).name.count, 255)
    }

    func testImageDimensionsAreBoundedAndMultipliedSafely() throws {
        XCTAssertThrowsError(try attachment(width: 0))
        XCTAssertThrowsError(try attachment(width: 12_001))
        XCTAssertThrowsError(try attachment(height: 12_001))
        XCTAssertNoThrow(try attachment(width: 12_000, height: 3_333))
        XCTAssertNoThrow(try attachment(width: 8_000, height: 5_000), "40 mégapixels exactement")
        XCTAssertThrowsError(try attachment(width: 12_000, height: 12_000), "144 mégapixels")
        XCTAssertThrowsError(try attachment(width: 2_048, height: nil), "Une image sans les deux dimensions est refusée")
        XCTAssertThrowsError(try attachment(width: nil, height: nil), "Une image sans dimensions est refusée")
        XCTAssertNoThrow(try attachment(.pdf, name: "bilan.pdf", width: nil, height: nil),
                         "Un PDF n'exige pas de dimensions image")
        XCTAssertThrowsError(try attachment(width: Int.max, height: 2), "La multiplication ne déborde pas")
    }

    func testMediaCryptoMetadataIsValidatedByThePrimitive() throws {
        let invalid = MessagingMediaEncryptionInfo(v: "v3", key: fileInfo().key, iv: fileInfo().iv, hashes: fileInfo().hashes)
        XCTAssertThrowsError(try MessagingMediaAttachment(id: mediaID, size: 10, mime: .jpeg, name: "a.jpg",
                                                          width: 1, height: 1, file: invalid)) { error in
            XCTAssertEqual(error as? MessagingFailure, .invalidResponse)
        }
        // Un alphabet inversé n'est pas normalisé : une clé qui contient `+` ou `/` est refusée.
        let standardKey = MessagingMediaEncryptionInfo(v: "v2",
            key: .init(kty: "oct", alg: "A256CTR", ext: true,
                       k: MessagingMediaBase64.encode(Data(repeating: 0xFF, count: 32), alphabet: .standard),
                       keyOps: ["decrypt", "encrypt"]),
            iv: MessagingMediaBase64.encode(Data(repeating: 0, count: 16), alphabet: .standard),
            hashes: .init(sha256: MessagingMediaBase64.encode(Data(repeating: 9, count: 32), alphabet: .standard)))
        XCTAssertTrue(standardKey.key.k.contains("/"), "La clé de ce cas est bien hors alphabet base64url")
        XCTAssertThrowsError(try MessagingMediaAttachment(id: mediaID, size: 10, mime: .jpeg, name: "a.jpg",
                                                          width: 1, height: 1, file: standardKey))
    }

    // MARK: Lecture : compatibilité et échecs fermés

    func testUnknownNamespacedVersionRendersTheReadableBody() throws {
        let payload = Data(#"{"msgtype":"m.text","body":"Photo","ch.drivy.messaging":{"v":4,"whatever":true}}"#.utf8)
        let decoded = try XCTUnwrap(MessagingPlainContent.decode(payload))
        XCTAssertEqual(decoded.text, "Photo")
        XCTAssertNil(decoded.media)
        XCTAssertFalse(decoded.text?.contains("{") ?? true, "Jamais de JSON technique brut")
    }

    func testKnownVersionThreeWithoutUsableMediaIsUnreadable() throws {
        let missingMedia = Data(#"{"msgtype":"m.text","body":"Photo","ch.drivy.messaging":{"v":3,"text":null}}"#.utf8)
        XCTAssertNil(MessagingPlainContent.decode(missingMedia), "v3 connu mais incomplet : échec fermé")
        let brokenSize = Data(#"{"msgtype":"m.text","body":"Photo","ch.drivy.messaging":{"v":3,"media":{"id":"\#(mediaID)","size":0,"mime":"image/jpeg","name":"a.jpg","width":1,"height":1,"file":{"v":"v2","key":{"kty":"oct","alg":"A256CTR","ext":true,"k":"\#(String(repeating: "A", count: 43))","key_ops":["decrypt","encrypt"]},"iv":"\#(String(repeating: "A", count: 22))","hashes":{"sha256":"\#(String(repeating: "A", count: 43))"}}}}}"#.utf8)
        XCTAssertNil(MessagingPlainContent.decode(brokenSize), "Une taille hors plafond n'ouvre aucun chemin")
        let missingBody = Data(#"{"msgtype":"m.text","ch.drivy.messaging":{"v":3}}"#.utf8)
        XCTAssertNil(MessagingPlainContent.decode(missingBody))
    }

    /// Une ancienne intention dont le texte ressemble à du JSON reste du texte utilisateur.
    func testLegacyTextLookingLikeJSONStaysUserText() throws {
        let raw = #"{"media":{"id":"5c1f"},"v":3}"#
        XCTAssertEqual(MessagingPlainContent.decode(Data(raw.utf8))?.text, raw)
        XCTAssertNil(MessagingPlainContent.decode(Data(raw.utf8))?.media)
        let matrixShapedButNotNamespaced = #"{"msgtype":"m.text","body":"coucou"}"#
        XCTAssertEqual(MessagingPlainContent.decode(Data(matrixShapedButNotNamespaced.utf8))?.text,
                       matrixShapedButNotNamespaced)
    }
}

private extension Data {
    /// Le `body` d'un contenu Matrix complet, sans passer par le modèle.
    var bodyText: String? {
        guard let decoded = try? JSONSerialization.jsonObject(with: self),
              let object = decoded as? [String: Any] else { return nil }
        return object["body"] as? String
    }
}
