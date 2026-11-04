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

        let cryptography = AESCTRMediaCryptography()
        for entry in cases {
            let id = try XCTUnwrap(entry["id"] as? String)
            let byteSize = try XCTUnwrap(entry["byteSize"] as? Int)
            let ciphertext = try MessagingMediaBase64.decode(
                try XCTUnwrap(entry["ciphertext"] as? String), alphabet: .standard, count: byteSize)
            let infoData = try JSONSerialization.data(
                withJSONObject: try XCTUnwrap(entry["info"]), options: [.sortedKeys])
            let decoded = try? JSONDecoder().decode(MessagingMediaEncryptionInfo.self, from: infoData)

            // Refus à l'entrée : structure illisible, ou objet lisible mais invalide
            // (version, en-tête JWK, alphabet, longueur, remplissage) avant tout
            // déchiffrement. Drivy refuse aussi tôt `v` inconnu et l'absence de
            // sha256, que ruma ne rejette qu'à la création du déchiffreur.
            let refusedBeforeDecryption = decoded.map { (try? $0.validatedMaterial()) == nil } ?? true
            XCTAssertTrue(refusedBeforeDecryption, "\(id) : refusé avant tout déchiffrement")

            if let decoded {
                XCTAssertFalse(cryptography.verify(ciphertext, info: decoded), id)
                XCTAssertThrowsError(try cryptography.open(ciphertext, info: decoded), id)
            }
        }
    }

    func testPaddedInputIsToleratedAndNeverReemitted() throws {
        let raw = try rawFixture()
        let cases = try XCTUnwrap(raw["padding"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)

        let cryptography = AESCTRMediaCryptography()
        for entry in cases {
            let id = try XCTUnwrap(entry["id"] as? String)
            let byteSize = try XCTUnwrap(entry["byteSize"] as? Int)
            let ciphertext = try MessagingMediaBase64.decode(
                try XCTUnwrap(entry["ciphertext"] as? String), alphabet: .standard, count: byteSize)
            let paddedData = try JSONSerialization.data(
                withJSONObject: try XCTUnwrap(entry["paddedInfo"]), options: [.sortedKeys])
            let padded = try JSONDecoder().decode(MessagingMediaEncryptionInfo.self, from: paddedData)
            XCTAssertEqual(try cryptography.open(ciphertext, info: padded),
                           mediaPlaintext(byteSize), id)
            XCTAssertTrue(cryptography.verify(ciphertext, info: padded), id)

            let canonicalData = try JSONSerialization.data(
                withJSONObject: try XCTUnwrap(entry["canonicalInfo"]), options: [.sortedKeys])
            let canonical = try JSONDecoder().decode(MessagingMediaEncryptionInfo.self, from: canonicalData)
            let material = try padded.validatedMaterial()
            let reemitted = MessagingMediaEncryptionInfo(
                key: material.key, iv: material.iv, sha256: material.sha256)
            XCTAssertEqual(try canonicalJSON(reemitted), try canonicalJSON(canonical), id)
            for text in [reemitted.key.k, reemitted.iv, reemitted.hashes.sha256] {
                XCTAssertFalse(text.contains("="), "\(id) : aucun remplissage réémis")
            }
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
