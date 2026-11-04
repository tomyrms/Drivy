import Foundation
import CommonCrypto
import CryptoKit
import Security

/// Objet `file` du contenu v3 (#97) : version, clé, IV et hash du chiffré.
///
/// Forme exacte du contrat `medias-exploitation-contrat-20261104.md` §4.2/§4.3 :
/// `k` en base64url, `iv` et `hashes.sha256` en base64 standard, tous **sans
/// remplissage**. Le décodage JSON n'accepte rien d'autre que cette forme ; la
/// validation des alphabets, des longueurs et des en-têtes JWK se fait dans
/// `validatedMaterial()`, avant tout déchiffrement.
struct MessagingMediaEncryptionInfo: Codable, Sendable, Equatable {
    struct Key: Codable, Sendable, Equatable {
        let kty: String
        let alg: String
        let ext: Bool
        /// Clé AES-256, base64url sans remplissage (43 caractères pour 32 octets).
        let k: String
        let keyOps: [String]

        enum CodingKeys: String, CodingKey {
            case kty, alg, ext, k
            case keyOps = "key_ops"
        }

        init(kty: String, alg: String, ext: Bool, k: String, keyOps: [String]) {
            self.kty = kty; self.alg = alg; self.ext = ext; self.k = k; self.keyOps = keyOps
        }
    }

    struct Hashes: Codable, Sendable, Equatable {
        /// SHA-256 du **chiffré**, base64 standard sans remplissage.
        let sha256: String

        init(sha256: String) { self.sha256 = sha256 }
    }

    let v: String
    let key: Key
    let iv: String
    let hashes: Hashes

    init(v: String, key: Key, iv: String, hashes: Hashes) {
        self.v = v; self.key = key; self.iv = iv; self.hashes = hashes
    }

    /// Écriture canonique : `v2`, `oct`, `A256CTR`, `ext` vrai, `["decrypt", "encrypt"]`,
    /// aucun remplissage. Seul constructeur utilisé pour sceller.
    init(key: Data, iv: Data, sha256: Data) {
        self.init(
            v: Self.version,
            key: Key(kty: "oct", alg: "A256CTR", ext: true,
                     k: MessagingMediaBase64.encode(key, alphabet: .urlSafe),
                     keyOps: ["decrypt", "encrypt"]),
            iv: MessagingMediaBase64.encode(iv, alphabet: .standard),
            hashes: Hashes(sha256: MessagingMediaBase64.encode(sha256, alphabet: .standard)))
    }

    static let version = "v2"

    /// Valide strictement l'objet, puis rend les octets à utiliser. Toute
    /// divergence est refusée avant déchiffrement, sans exposer de valeur.
    func validatedMaterial() throws -> MessagingMediaMaterial {
        guard v == Self.version, key.kty == "oct", key.alg == "A256CTR", key.ext else {
            throw MessagingMediaCryptographyFailure.invalidEncryptionInfo
        }
        guard key.keyOps.contains("encrypt"), key.keyOps.contains("decrypt") else {
            throw MessagingMediaCryptographyFailure.invalidEncryptionInfo
        }
        return MessagingMediaMaterial(
            key: try MessagingMediaBase64.decode(key.k, alphabet: .urlSafe, count: 32),
            iv: try MessagingMediaBase64.decode(iv, alphabet: .standard, count: 16),
            sha256: try MessagingMediaBase64.decode(hashes.sha256, alphabet: .standard, count: 32))
    }
}

/// Octets validés d'un média scellé. Aucun accès public : seul le module de
/// chiffrement manipule la clé.
struct MessagingMediaMaterial: Sendable, Equatable {
    let key: Data
    let iv: Data
    let sha256: Data
}

/// Primitive des pièces jointes chiffrées (#97) : sceller, ouvrir, vérifier.
/// Aucune de ces opérations ne touche au disque, au réseau ou à un identifiant
/// de personne : l'identifiant média est un UUID local.
protocol MessagingMediaCryptography: Sendable {
    /// Chiffre un clair et produit un objet immuable réutilisable tel quel en cas de nouvel essai.
    func seal(_ plaintext: Data) throws -> MessagingSealedMedia
    /// Vérifie l'intégrité du chiffré **avant** de rendre le clair.
    func open(_ ciphertext: Data, info: MessagingMediaEncryptionInfo) throws -> Data
    /// Contrôle d'intégrité seul : ne produit aucun clair et ne lève jamais.
    func verify(_ ciphertext: Data, info: MessagingMediaEncryptionInfo) -> Bool
}

/// Pièce jointe chiffrée prête à déposer. Immuable : un nouvel essai réseau
/// réutilise exactement ces octets et cet identifiant.
struct MessagingSealedMedia: Sendable, Equatable {
    let mediaID: UUID
    let ciphertext: Data
    let info: MessagingMediaEncryptionInfo
    var byteSize: Int { ciphertext.count }
}

/// Erreurs fermées de la primitive média : aucune valeur reçue n'y est attachée,
/// donc aucun octet, identifiant, nom, clé ni hash ne peut sortir par un message.
enum MessagingMediaCryptographyFailure: Error, Equatable, Sendable, LocalizedError {
    /// Clair ou chiffré au-delà du plafond de 4 Mio (ou taille refusée par l'appelant).
    case invalidSize
    /// Version, en-tête JWK, alphabet, longueur décodée ou remplissage non conformes.
    case invalidEncryptionInfo
    /// SHA-256 du chiffré différent de celui annoncé : le clair n'est jamais rendu.
    case integrityMismatch
    /// Aléa système indisponible : aucun média n'est scellé avec une clé faible.
    case randomnessUnavailable
    /// AES-CTR indisponible ou sortie incohérente.
    case cipherUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSize: "Ce fichier est trop volumineux pour être joint."
        case .invalidEncryptionInfo: "Les informations de chiffrement de cette pièce jointe sont invalides."
        case .integrityMismatch: "Ce fichier est illisible : son intégrité n'a pas pu être vérifiée."
        case .randomnessUnavailable, .cipherUnavailable: "Le chiffrement de cette pièce jointe est indisponible sur cet appareil."
        }
    }
}

/// Chiffrement des pièces jointes de la messagerie (#97), format Matrix
/// « encrypted attachments v2 » (https://spec.matrix.org/v1.17/client-server-api/#sending-encrypted-attachments).
///
/// AES-256-CTR (CommonCrypto, compteur 64 bits big-endian) + SHA-256 du chiffré
/// (CryptoKit). La voie est une implémentation du format publié, pas un appel au
/// module amont : la fidélité est prouvée par les vecteurs croisés produits par
/// `matrix-sdk-crypto` 0.19.1 (`prototypes/messaging-crypto/tests/media_vectors.rs`).
struct AESCTRMediaCryptography: MessagingMediaCryptography {
    /// Plafond produit : 4 Mio de clair, donc 4 Mio de chiffré (CTR sans remplissage).
    static let maximumByteSize = 4_194_304

    /// Clé et IV du harnais de vecteurs. `nil` en production : chaque sceau tire
    /// une clé et un IV neufs.
    private let reserved: (key: Data, iv: Data)?

    init() {
        reserved = nil
    }

    /// Réservé au harnais de vecteurs croisés (§4.3.4) : rejoue une clé et un IV
    /// enregistrés pour comparer les octets avec l'oracle Rust. Jamais utilisé par
    /// l'app, jamais transmis, jamais persisté.
    init(reservedKey: Data, reservedIV: Data) throws {
        guard reservedKey.count == 32 else { throw MessagingMediaCryptographyFailure.invalidEncryptionInfo }
        guard reservedIV.count == 16, reservedIV.suffix(8).allSatisfy({ $0 == 0 }) else {
            throw MessagingMediaCryptographyFailure.invalidEncryptionInfo
        }
        reserved = (reservedKey, reservedIV)
    }

    // MARK: MessagingMediaCryptography

    func seal(_ plaintext: Data) throws -> MessagingSealedMedia {
        guard plaintext.count <= Self.maximumByteSize else {
            throw MessagingMediaCryptographyFailure.invalidSize
        }
        let (key, iv) = try freshMaterial()
        let ciphertext = try Self.transform(plaintext, key: key, iv: iv)
        let digest = Data(SHA256.hash(data: ciphertext))
        return MessagingSealedMedia(
            mediaID: UUID(),
            ciphertext: ciphertext,
            info: MessagingMediaEncryptionInfo(key: key, iv: iv, sha256: digest))
    }

    func open(_ ciphertext: Data, info: MessagingMediaEncryptionInfo) throws -> Data {
        guard ciphertext.count <= Self.maximumByteSize else {
            throw MessagingMediaCryptographyFailure.invalidSize
        }
        let material = try info.validatedMaterial()
        guard Self.constantTimeEqual(Self.digest(ciphertext), material.sha256) else {
            throw MessagingMediaCryptographyFailure.integrityMismatch
        }
        return try Self.transform(ciphertext, key: material.key, iv: material.iv)
    }

    func verify(_ ciphertext: Data, info: MessagingMediaEncryptionInfo) -> Bool {
        guard ciphertext.count <= Self.maximumByteSize,
              let material = try? info.validatedMaterial() else { return false }
        return Self.constantTimeEqual(Self.digest(ciphertext), material.sha256)
    }

    // MARK: Interne

    private func freshMaterial() throws -> (key: Data, iv: Data) {
        if let reserved { return reserved }
        var key = Data(count: 32)
        try key.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            guard let base = buffer.baseAddress else { throw MessagingMediaCryptographyFailure.randomnessUnavailable }
            guard SecRandomCopyBytes(kSecRandomDefault, 32, base) == errSecSuccess else {
                throw MessagingMediaCryptographyFailure.randomnessUnavailable
            }
        }
        // IV = 8 octets aléatoires puis 8 octets à zéro : le compteur 64 bits part de 0.
        var iv = Data(count: 16)
        try iv.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            guard let base = buffer.baseAddress else { throw MessagingMediaCryptographyFailure.randomnessUnavailable }
            guard SecRandomCopyBytes(kSecRandomDefault, 8, base) == errSecSuccess else {
                throw MessagingMediaCryptographyFailure.randomnessUnavailable
            }
        }
        return (key, iv)
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// Comparaison sans sortie anticipée : le contexte (hash d'intégrité, jamais
    /// une clé) ne justifie pas un `==` d'octets.
    private static func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    /// AES-256-CTR avec compteur big-endian, sans remplissage : la taille de
    /// sortie est celle de l'entrée.
    private static func transform(_ input: Data, key: Data, iv: Data) throws -> Data {
        guard !input.isEmpty else { return Data() }
        guard key.count == 32, iv.count == 16 else {
            throw MessagingMediaCryptographyFailure.invalidEncryptionInfo
        }

        var cryptor: CCCryptorRef?
        let created = key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer) -> CCCryptorStatus in
            iv.withUnsafeBytes { (ivBytes: UnsafeRawBufferPointer) -> CCCryptorStatus in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding), ivBytes.baseAddress, keyBytes.baseAddress, key.count,
                    nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
            }
        }
        guard created == kCCSuccess, let cryptor else {
            throw MessagingMediaCryptographyFailure.cipherUnavailable
        }
        defer { _ = CCCryptorRelease(cryptor) }

        var output = Data(count: input.count)
        var moved = 0
        let written = output.withUnsafeMutableBytes { (outputBytes: UnsafeMutableRawBufferPointer) -> CCCryptorStatus in
            input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> CCCryptorStatus in
                CCCryptorUpdate(cryptor, inputBytes.baseAddress, input.count,
                                outputBytes.baseAddress, outputBytes.count, &moved)
            }
        }
        guard written == kCCSuccess, moved == input.count else {
            throw MessagingMediaCryptographyFailure.cipherUnavailable
        }
        return output
    }
}

/// Encodage/décodage base64 du format média, volontairement autonome : la
/// bibliothèque amont accepte un remplissage en lecture (`Indifferent`), ignore
/// les bits de queue et n'émet aucun remplissage. `Data(base64Encoded:)` ne
/// garantit pas ces règles, donc les trois alphabets sont traités ici.
enum MessagingMediaBase64 {
    enum Alphabet {
        /// `A–Z a–z 0–9 + /`
        case standard
        /// `A–Z a–z 0–9 - _`
        case urlSafe
    }

    static func encode(_ data: Data, alphabet: Alphabet) -> String {
        let symbols = Array(table(alphabet))
        var out = ""
        out.reserveCapacity((data.count + 2) / 3 * 4)
        var index = data.startIndex
        while index < data.endIndex {
            let remaining = data.distance(from: index, to: data.endIndex)
            let first = Int(data[index])
            let second = remaining > 1 ? Int(data[data.index(after: index)]) : 0
            let third = remaining > 2 ? Int(data[data.index(index, offsetBy: 2)]) : 0
            let triple = (first << 16) | (second << 8) | third
            out.append(symbols[(triple >> 18) & 0x3F])
            out.append(symbols[(triple >> 12) & 0x3F])
            if remaining > 1 { out.append(symbols[(triple >> 6) & 0x3F]) }
            if remaining > 2 { out.append(symbols[triple & 0x3F]) }
            index = data.index(index, offsetBy: min(3, remaining))
        }
        return out
    }

    /// Décode en refusant tout ce que la bibliothèque refuse : caractère hors
    /// alphabet, remplissage mal placé ou non canonique, longueur impossible.
    /// Les bits de queue non nuls sont tolérés, comme dans `ruma`.
    static func decode(_ text: String, alphabet: Alphabet, count: Int) throws -> Data {
        var symbols = Array(text.utf8)
        var padding = 0
        while symbols.last == UInt8(ascii: "=") {
            padding += 1
            symbols.removeLast()
        }
        guard padding <= 2 else { throw MessagingMediaCryptographyFailure.invalidEncryptionInfo }
        if padding > 0 {
            guard (symbols.count + padding) % 4 == 0 else {
                throw MessagingMediaCryptographyFailure.invalidEncryptionInfo
            }
            let remainder = symbols.count % 4
            guard remainder != 0, padding == 4 - remainder else {
                throw MessagingMediaCryptographyFailure.invalidEncryptionInfo
            }
        }
        guard symbols.count % 4 != 1 else { throw MessagingMediaCryptographyFailure.invalidEncryptionInfo }

        let lookup = values(alphabet)
        var bytes = Data()
        bytes.reserveCapacity(count)
        var accumulator: UInt32 = 0
        var bits = 0
        for symbol in symbols {
            guard symbol < 128 else { throw MessagingMediaCryptographyFailure.invalidEncryptionInfo }
            let value = lookup[Int(symbol)]
            guard value != Self.invalidSymbol else {
                throw MessagingMediaCryptographyFailure.invalidEncryptionInfo
            }
            // Les décalages hors capacité abandonnent les bits déjà consommés ;
            // seuls les bits de queue non encore écrits sont relus ci-dessous.
            accumulator = (accumulator << 6) | UInt32(value)
            bits += 6
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((accumulator >> UInt32(bits)) & 0xFF))
            }
        }
        guard bytes.count == count else { throw MessagingMediaCryptographyFailure.invalidEncryptionInfo }
        return bytes
    }

    /// Valeur sentinelle : aucun symbole base64 ne porte l'indice 255.
    private static let invalidSymbol: UInt8 = 0xFF

    private static func table(_ alphabet: Alphabet) -> [Character] {
        let standard = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        switch alphabet {
        case .standard: return standard
        case .urlSafe: return Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        }
    }

    private static func values(_ alphabet: Alphabet) -> [UInt8] {
        var lookup = [UInt8](repeating: invalidSymbol, count: 128)
        for (index, symbol) in table(alphabet).enumerated() {
            guard let code = symbol.asciiValue else { continue }
            lookup[Int(code)] = UInt8(index)
        }
        return lookup
    }
}
