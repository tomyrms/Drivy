import XCTest
@testable import Drivy

/// Vecteurs croisés du format Matrix « encrypted attachments v2 » (#97, T2a).
///
/// Les octets attendus sont produits et relus par `matrix-sdk-crypto` 0.19.1
/// (`prototypes/messaging-crypto/tests/media_vectors.rs`) ; la fixture est
/// `Fixtures/media-vectors.json`, synthétique et sans secret réel.
///
/// Écrit mais **non exécuté** sur le poste d'implémentation (aucun Xcode) : la
/// preuve Apple vient d'un runner, au SHA du commit, et ne peut pas être
/// remplacée par les tests Rust.
final class MessagingMediaCryptographyTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Vector: Decodable {
            let id: String
            let byteSize: Int
            let ciphertext: String
            let info: MessagingMediaEncryptionInfo
        }

        struct Upstream: Decodable {
            let source: String
            let plaintext: String
            let ciphertext: [UInt8]
            let info: MessagingMediaEncryptionInfo
        }

        let format: String
        let oracle: String
        let plaintextRule: String
        let upstreamVector: Upstream
        let vectors: [Vector]
    }

    // MARK: Fixture

    private func fixtureData() throws -> Data {
        let bundle = Bundle(for: MessagingMediaCryptographyTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "media-vectors", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "media-vectors", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try fixtureData())
    }

    private func rawFixture() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try fixtureData())
        return try XCTUnwrap(object as? [String: Any])
    }

    private func referenceVector() throws -> Fixture.Vector {
        try XCTUnwrap(try fixture().vectors.first { $0.byteSize == 17 })
    }

    /// Harnais §4.3.4 : rejoue la clé et l'IV enregistrés par l'oracle.
    private func reservedCryptography(for info: MessagingMediaEncryptionInfo) throws -> AESCTRMediaCryptography {
        let material = try info.validatedMaterial()
        return try AESCTRMediaCryptography(reservedKey: material.key, reservedIV: material.iv)
    }

    // MARK: Sens Swift → oracle

    func testSealReproducesEveryOfficialVector() throws {
        let loaded = try fixture()
        XCTAssertEqual(loaded.format, "matrix-encrypted-attachment-v2")
        XCTAssertTrue(loaded.oracle.contains("0.19.1"))
        XCTAssertFalse(loaded.vectors.isEmpty)

        for vector in loaded.vectors {
            let expected = try MessagingMediaBase64.decode(
                vector.ciphertext, alphabet: .standard, count: vector.byteSize)
            let sealed = try reservedCryptography(for: vector.info).seal(mediaPlaintext(vector.byteSize))
            XCTAssertEqual(sealed.ciphertext, expected, vector.id)
            XCTAssertEqual(sealed.byteSize, vector.byteSize, vector.id)
            XCTAssertEqual(try canonicalJSON(sealed.info), try canonicalJSON(vector.info), vector.id)
            XCTAssertEqual(sealed.mediaID.uuidString.count, 36, vector.id)
        }
    }

    // MARK: Sens oracle → Swift

    func testOpenReadsEveryOfficialVector() throws {
        let cryptography = AESCTRMediaCryptography()
        for vector in try fixture().vectors {
            let ciphertext = try MessagingMediaBase64.decode(
                vector.ciphertext, alphabet: .standard, count: vector.byteSize)
            XCTAssertEqual(try cryptography.open(ciphertext, info: vector.info),
                           mediaPlaintext(vector.byteSize), vector.id)
            XCTAssertTrue(cryptography.verify(ciphertext, info: vector.info), vector.id)
        }
    }

    func testUpstreamVectorFromTheLinkedLibraryStillOpens() throws {
        let upstream = try fixture().upstreamVector
        XCTAssertTrue(upstream.source.contains("0.17.0"))
        let ciphertext = Data(upstream.ciphertext)

        let opened = try AESCTRMediaCryptography().open(ciphertext, info: upstream.info)
        XCTAssertEqual(String(decoding: opened, as: UTF8.self), "It's a secret to everybody")
        XCTAssertEqual(String(decoding: opened, as: UTF8.self), upstream.plaintext)

        // L'écriture Swift avec la clé/IV amont reproduit exactement les octets amont.
        let sealed = try reservedCryptography(for: upstream.info).seal(opened)
        XCTAssertEqual(sealed.ciphertext, ciphertext)
        XCTAssertEqual(try canonicalJSON(sealed.info), try canonicalJSON(upstream.info))
    }

    // MARK: Intégrité

    func testCorruptedCiphertextIsRefusedBeforeAnyPlaintext() throws {
        let vector = try referenceVector()
        var corrupted = try MessagingMediaBase64.decode(
            vector.ciphertext, alphabet: .standard, count: vector.byteSize)
        corrupted[corrupted.startIndex] ^= 0x01

        let cryptography = AESCTRMediaCryptography()
        XCTAssertFalse(cryptography.verify(corrupted, info: vector.info))
        XCTAssertThrowsError(try cryptography.open(corrupted, info: vector.info)) { error in
            XCTAssertEqual(error as? MessagingMediaCryptographyFailure, .integrityMismatch)
        }

        let truncated = corrupted.prefix(16)
        XCTAssertFalse(cryptography.verify(truncated, info: vector.info))
        XCTAssertThrowsError(try cryptography.open(truncated, info: vector.info)) { error in
            XCTAssertEqual(error as? MessagingMediaCryptographyFailure, .integrityMismatch)
        }
    }

    func testModifiedHashIsRefusedEvenWithAValidCiphertext() throws {
        let vector = try referenceVector()
        let other = try XCTUnwrap(try fixture().vectors.first { $0.byteSize == 16 })
        let ciphertext = try MessagingMediaBase64.decode(
            vector.ciphertext, alphabet: .standard, count: vector.byteSize)
        let wrongHash = MessagingMediaEncryptionInfo(
            v: MessagingMediaEncryptionInfo.version,
            key: MessagingMediaEncryptionInfo.Key(
                kty: "oct", alg: "A256CTR", ext: true,
                k: vector.info.key.k, keyOps: vector.info.key.keyOps),
            iv: vector.info.iv,
            hashes: MessagingMediaEncryptionInfo.Hashes(sha256: other.info.hashes.sha256))

        let cryptography = AESCTRMediaCryptography()
        XCTAssertFalse(cryptography.verify(ciphertext, info: wrongHash))
        XCTAssertThrowsError(try cryptography.open(ciphertext, info: wrongHash)) { error in
            XCTAssertEqual(error as? MessagingMediaCryptographyFailure, .integrityMismatch)
        }
    }

    // MARK: Validation stricte de l'objet

    func testInvalidInfosAreRefusedAtEntry() throws {
        let raw = try rawFixture()
        let cases = try XCTUnwrap(raw["rejections"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)

        for entry in cases {
            let id = try XCTUnwrap(entry["id"] as? String)
            let infoData = try JSONSerialization.data(
                withJSONObject: try XCTUnwrap(entry["info"]), options: [.sortedKeys])

            // Le décodage valide à l'entrée : version, en-tête JWK, alphabets,
            // longueurs et remplissage. Aucun objet invalide n'est construit,
            // donc aucun clair n'est possible. `refusedAt` rappelle seulement que
            // ruma refuse `v` inconnu et l'absence de sha256 plus tard, au
            // déchiffreur : Drivy refuse plus tôt, avec le même verdict final.
            XCTAssertNil(try? JSONDecoder().decode(MessagingMediaEncryptionInfo.self, from: infoData),
                         "\(id) : refusé avant tout déchiffrement")
        }
    }

    func testPaddingMatrixMatchesTheLibrary() throws {
        let raw = try rawFixture()
        let cases = try XCTUnwrap(raw["paddingMatrix"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12)

        for entry in cases {
            let id = try XCTUnwrap(entry["id"] as? String)
            let alphabet: MessagingMediaBase64.Alphabet =
                try XCTUnwrap(entry["alphabet"] as? String) == "urlSafe" ? .urlSafe : .standard
            let count = try XCTUnwrap(entry["count"] as? Int)
            let encoded = try XCTUnwrap(entry["encoded"] as? String)
            let accepted = try XCTUnwrap(entry["accepted"] as? Bool)

            if accepted {
                let decoded = try MessagingMediaBase64.decode(encoded, alphabet: alphabet, count: count)
                XCTAssertEqual(decoded.count, try XCTUnwrap(entry["decodedLength"] as? Int), id)
                let canonical = try MessagingMediaBase64.decode(
                    try XCTUnwrap(entry["decodedBase64Standard"] as? String),
                    alphabet: .standard, count: count)
                XCTAssertEqual(decoded, canonical, "\(id) : mêmes octets que l'oracle")
            } else {
                XCTAssertThrowsError(
                    try MessagingMediaBase64.decode(encoded, alphabet: alphabet, count: count),
                    "\(id) : refusé comme par la bibliothèque")
            }
        }
    }

    func testEncodedLengthLimitMatchesTheFixtureAndBoundsInputs() throws {
        let raw = try rawFixture()
        let limits = try XCTUnwrap(raw["limits"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(limits["maximumByteSize"] as? Int),
                       AESCTRMediaCryptography.maximumByteSize)
        let entries = try XCTUnwrap(limits["perSize"] as? [[String: Any]])
        let vectors = try XCTUnwrap(raw["vectors"] as? [[String: Any]])
        XCTAssertEqual(entries.count, vectors.count)

        for entry in entries {
            let byteSize = try XCTUnwrap(entry["byteSize"] as? Int)
            let limit = try XCTUnwrap(entry["encodedLengthLimit"] as? Int)
            XCTAssertEqual(MessagingMediaBase64.maximumEncodedLength(for: byteSize), limit, "\(byteSize)")
            let vector = try XCTUnwrap(vectors.first { $0["byteSize"] as? Int == byteSize })
            let encoded = try XCTUnwrap(vector["ciphertext"] as? String)
            XCTAssertLessThanOrEqual(encoded.utf8.count, limit, "\(byteSize) : encodage réel dans la borne")
            XCTAssertLessThanOrEqual(encoded.utf8.count + 2, limit, "\(byteSize) : deux « = » tiendraient")
        }
    }

    func testOversizedAndMalformedInputsAreRefusedBeforeAllocation() throws {
        let vector = try referenceVector()
        let oversized = String(repeating: "A", count: 4_096)

        // Borne dérivée de la taille attendue, vérifiée avant toute copie : une
        // clé de 32 octets (45 caractères au plus) ne peut pas faire 4 096 octets.
        XCTAssertThrowsError(try MessagingMediaBase64.decode(oversized, alphabet: .urlSafe, count: 32))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(oversized, alphabet: .standard, count: 16))
        XCTAssertEqual(MessagingMediaBase64.maximumEncodedLength(for: 32), 45)
        XCTAssertEqual(MessagingMediaBase64.maximumEncodedLength(for: 16), 24)
        XCTAssertEqual(MessagingMediaBase64.maximumEncodedLength(for: 0), 2)

        // `count` hors plafond, non-ASCII, blanc, remplissage excessif ou interne.
        XCTAssertThrowsError(try MessagingMediaBase64.decode("", alphabet: .standard, count: -1))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(
            "", alphabet: .standard, count: AESCTRMediaCryptography.maximumByteSize + 1))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(
            String(vector.info.iv.dropLast()) + "é", alphabet: .standard, count: 16))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(vector.info.iv + "===", alphabet: .standard, count: 16))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(
            String(vector.info.iv.prefix(18)) + "====", alphabet: .standard, count: 16))
        XCTAssertThrowsError(try MessagingMediaBase64.decode("A=", alphabet: .standard, count: 1))
    }

    func testPaddedInputIsToleratedAndNeverReemitted() throws {
        let raw = try rawFixture()
        let cases = try XCTUnwrap(raw["padding"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 2)

        let cryptography = AESCTRMediaCryptography()
        for entry in cases {
            let id = try XCTUnwrap(entry["id"] as? String)
            let byteSize = try XCTUnwrap(entry["byteSize"] as? Int)
            let ciphertext = try MessagingMediaBase64.decode(
                try XCTUnwrap(entry["ciphertext"] as? String), alphabet: .standard, count: byteSize)
            let paddedData = try JSONSerialization.data(
                withJSONObject: try XCTUnwrap(entry["paddedInfo"]), options: [.sortedKeys])

            // Chemin réel : l'objet décodé est déjà canonique, sans reconstruire
            // un second objet comme le faisait la version précédente du test.
            let padded = try JSONDecoder().decode(MessagingMediaEncryptionInfo.self, from: paddedData)
            XCTAssertEqual(try cryptography.open(ciphertext, info: padded),
                           mediaPlaintext(byteSize), id)
            XCTAssertTrue(cryptography.verify(ciphertext, info: padded), id)
            for text in [padded.key.k, padded.iv, padded.hashes.sha256] {
                XCTAssertFalse(text.contains("="), "\(id) : aucun remplissage conservé à la lecture")
            }

            let canonicalData = try JSONSerialization.data(
                withJSONObject: try XCTUnwrap(entry["canonicalInfo"]), options: [.sortedKeys])
            let canonical = try JSONDecoder().decode(MessagingMediaEncryptionInfo.self, from: canonicalData)
            XCTAssertEqual(try canonicalJSON(padded), try canonicalJSON(canonical),
                           "\(id) : aller-retour JSONDecoder → JSONEncoder canonique")
        }
    }

    // MARK: Aléa, tailles, absence de fuite

    func testEverySealUsesFreshKeyAndIV() throws {
        let cryptography = AESCTRMediaCryptography()
        let plaintext = Data("pièce jointe synthétique".utf8)
        var keys = Set<String>(), ivs = Set<String>(), identifiers = Set<UUID>()

        for _ in 0..<64 {
            let sealed = try cryptography.seal(plaintext)
            let material = try sealed.info.validatedMaterial()
            XCTAssertEqual(material.key.count, 32)
            XCTAssertEqual(material.iv.count, 16)
            XCTAssertEqual(material.sha256.count, 32)
            XCTAssertEqual(material.iv.suffix(8), Data(repeating: 0, count: 8), "compteur 64 bits à zéro")
            XCTAssertEqual(sealed.byteSize, plaintext.count)
            XCTAssertFalse(sealed.info.key.k.contains("+") || sealed.info.key.k.contains("/"))
            XCTAssertFalse(sealed.info.key.k.contains("="))
            XCTAssertFalse(sealed.info.iv.contains("="))
            XCTAssertFalse(sealed.info.hashes.sha256.contains("="))
            XCTAssertEqual(try cryptography.open(sealed.ciphertext, info: sealed.info), plaintext)
            keys.insert(sealed.info.key.k)
            ivs.insert(sealed.info.iv)
            identifiers.insert(sealed.mediaID)
        }

        XCTAssertEqual(keys.count, 64, "aucune clé réutilisée")
        XCTAssertEqual(ivs.count, 64, "aucun IV réutilisé")
        XCTAssertEqual(identifiers.count, 64, "un identifiant média par sceau")
    }

    func testPayloadBoundsAcceptZeroAndTheLimitAndRejectBeyond() throws {
        let cryptography = AESCTRMediaCryptography()

        let empty = try cryptography.seal(Data())
        XCTAssertEqual(empty.ciphertext.count, 0)
        XCTAssertEqual(empty.info.hashes.sha256.count, 43)
        XCTAssertEqual(try cryptography.open(Data(), info: empty.info), Data())
        XCTAssertTrue(cryptography.verify(Data(), info: empty.info))

        let limit = Data(repeating: 0x5A, count: AESCTRMediaCryptography.maximumByteSize)
        let sealed = try cryptography.seal(limit)
        XCTAssertEqual(sealed.ciphertext.count, limit.count)
        XCTAssertEqual(try cryptography.open(sealed.ciphertext, info: sealed.info), limit)

        let beyond = Data(repeating: 0x5A, count: AESCTRMediaCryptography.maximumByteSize + 1)
        XCTAssertThrowsError(try cryptography.seal(beyond)) { error in
            XCTAssertEqual(error as? MessagingMediaCryptographyFailure, .invalidSize)
        }
        XCTAssertThrowsError(try cryptography.open(beyond, info: sealed.info)) { error in
            XCTAssertEqual(error as? MessagingMediaCryptographyFailure, .invalidSize)
        }
        XCTAssertFalse(cryptography.verify(beyond, info: sealed.info))
    }

    func testErrorsCarryNoKeyCiphertextOrHash() throws {
        let vector = try referenceVector()
        let ciphertext = try MessagingMediaBase64.decode(
            vector.ciphertext, alphabet: .standard, count: vector.byteSize)
        let forbidden = [
            vector.info.key.k,
            vector.info.iv,
            vector.info.hashes.sha256,
            ciphertext.map { String(format: "%02x", $0) }.joined(),
        ]
        let failures: [MessagingMediaCryptographyFailure] = [
            .invalidSize, .invalidEncryptionInfo, .integrityMismatch, .randomnessUnavailable, .cipherUnavailable,
        ]

        for failure in failures {
            for text in [String(describing: failure), failure.localizedDescription] {
                for value in forbidden {
                    XCTAssertFalse(text.contains(value), "aucune donnée sensible dans l'erreur")
                }
            }
        }
    }

    func testBase64RulesMatchTheLibrary() throws {
        let bytes = Data((0..<32).map { UInt8($0) })
        let standard = MessagingMediaBase64.encode(bytes, alphabet: .standard)
        let urlSafe = MessagingMediaBase64.encode(bytes, alphabet: .urlSafe)
        XCTAssertEqual(standard.count, 43)
        XCTAssertEqual(urlSafe.count, 43)
        XCTAssertFalse(standard.contains("="))
        XCTAssertEqual(try MessagingMediaBase64.decode(standard, alphabet: .standard, count: 32), bytes)
        XCTAssertEqual(try MessagingMediaBase64.decode(urlSafe, alphabet: .urlSafe, count: 32), bytes)

        // Remplissage toléré en lecture, jamais émis en écriture.
        XCTAssertEqual(try MessagingMediaBase64.decode(standard + "=", alphabet: .standard, count: 32), bytes)

        // Alphabets croisés : 0xFB produit « + / » en standard et « - _ » en url.
        let symbols = Data(repeating: 0xFB, count: 32)
        let standardSymbols = MessagingMediaBase64.encode(symbols, alphabet: .standard)
        let urlSafeSymbols = MessagingMediaBase64.encode(symbols, alphabet: .urlSafe)
        XCTAssertTrue(standardSymbols.contains("+") || standardSymbols.contains("/"))
        XCTAssertTrue(urlSafeSymbols.contains("-") || urlSafeSymbols.contains("_"))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(standardSymbols, alphabet: .urlSafe, count: 32))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(urlSafeSymbols, alphabet: .standard, count: 32))

        // Longueur décodée, remplissage mal formé, caractère hors alphabet.
        XCTAssertThrowsError(try MessagingMediaBase64.decode(urlSafe, alphabet: .urlSafe, count: 31))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(standard + "==", alphabet: .standard, count: 32))
        XCTAssertThrowsError(try MessagingMediaBase64.decode(standard + "\n", alphabet: .standard, count: 32))
    }

    func testPlaintextRuleIsTheDocumentedSyntheticPattern() {
        XCTAssertEqual(mediaPlaintext(0).count, 0)
        XCTAssertEqual(Array(mediaPlaintext(17)),
                       [7, 38, 69, 100, 131, 162, 193, 224, 255, 30, 61, 92, 123, 154, 185, 216, 247])
    }
}

// MARK: Aides de fichier

/// Règle de clair partagée avec `prototypes/messaging-crypto/tests/media_vectors.rs` :
/// `byte(i) = u8(7 + 31*i + (i >> 8))`. Aucun octet stocké pour le cas 4 Mio.
private func mediaPlaintext(_ count: Int) -> Data {
    var data = Data(capacity: count)
    for index in 0..<count {
        data.append(UInt8(truncatingIfNeeded: 7 &+ 31 &* UInt64(index) &+ (UInt64(index) >> 8)))
    }
    return data
}

/// JSON canonique (clés triées, sans espaces) pour comparer une sérialisation
/// Swift à celle de l'oracle, indépendamment de l'ordre de déclaration.
private func canonicalJSON(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func canonicalJSON(_ info: MessagingMediaEncryptionInfo) throws -> String {
    let encoded = try JSONEncoder().encode(info)
    let object = try JSONSerialization.jsonObject(with: encoded)
    return try canonicalJSON(object)
}
