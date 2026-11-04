import Foundation

/// Pièce jointe déclarée dans le contenu v3 `ch.drivy.messaging` (#97, contrat §4.2).
///
/// Champs exacts : `id`, `size`, `mime`, `name`, `width`, `height`, `file`. Aucune
/// ressource distante : il n'existe ni URL de téléchargement, ni aperçu de lien, ni
/// miniature, ni chemin local. Le nom est une donnée d'affichage assainie, jamais un
/// chemin.
///
/// Invariant du type : un objet construit est **valide et déjà assaini** — la taille est
/// dans le plafond, le MIME dans la liste, le nom nettoyé et borné, les dimensions
/// contrôlées, les métadonnées crypto validées par la primitive (`MessagingMediaEncryptionInfo`).
/// Le décodage passe par le même initialiseur : un média reçu invalide échoue fermé.
struct MessagingMediaAttachment: Codable, Sendable, Equatable {
    /// Types acceptés par le contrat. Un autre type n'ouvre aucun chemin.
    enum MIME: String, Codable, Sendable, Equatable, CaseIterable {
        case jpeg = "image/jpeg"
        case png = "image/png"
        case pdf = "application/pdf"

        var isImage: Bool { self != .pdf }

        /// Repli lisible du `body` pour un client qui ignore la namespace.
        var fallbackBody: String {
            switch self {
            case .jpeg, .png: "Photo"
            case .pdf: "PDF"
            }
        }
    }

    /// Plafond produit : un fichier par message, 4 Mio (mandat du 4 novembre 2026).
    static let maximumByteSize = 4_194_304
    /// Un média de zéro octet n'est pas une pièce jointe.
    static let minimumByteSize = 1
    static let maximumNameLength = 255
    static let maximumPixelsPerAxis = 12_000
    static let maximumPixels = 40_000_000

    let id: UUID
    let size: Int
    let mime: MIME
    let name: String
    let width: Int?
    let height: Int?
    let file: MessagingMediaEncryptionInfo

    /// Assainit et valide à la construction : aucune valeur non conforme ne peut être émise.
    init(id: UUID, size: Int, mime: MIME, name: String, width: Int? = nil, height: Int? = nil,
         file: MessagingMediaEncryptionInfo) throws {
        guard (Self.minimumByteSize...Self.maximumByteSize).contains(size) else {
            throw MessagingFailure.invalidResponse
        }
        guard let name = MessagingMediaName.sanitized(name) else { throw MessagingFailure.invalidResponse }
        try Self.validate(mime: mime, width: width, height: height)
        guard (try? file.validatedMaterial()) != nil else { throw MessagingFailure.invalidResponse }
        self.id = id
        self.size = size
        self.mime = mime
        self.name = name
        self.width = width
        self.height = height
        self.file = file
    }

    /// Lecture stricte : un média reçu qui ne satisfait pas le contrat échoue, sans normaliser d'alphabet crypto.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let size = try container.decode(Int.self, forKey: .size)
        let mime = try container.decode(MIME.self, forKey: .mime)
        let name = try container.decode(String.self, forKey: .name)
        let width = try container.decodeIfPresent(Int.self, forKey: .width)
        let height = try container.decodeIfPresent(Int.self, forKey: .height)
        let file = try container.decode(MessagingMediaEncryptionInfo.self, forKey: .file)
        do {
            try self.init(id: id, size: size, mime: mime, name: name, width: width, height: height, file: file)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .size, in: container,
                                                  debugDescription: "invalid media")
        }
    }

    /// Dimensions : les deux, ou aucune. Une image exige les deux ; un PDF n'en a pas besoin.
    private static func validate(mime: MIME, width: Int?, height: Int?) throws {
        switch (width, height) {
        case (nil, nil):
            guard !mime.isImage else { throw MessagingFailure.invalidResponse }
        case let (.some(width), .some(height)):
            guard (1...maximumPixelsPerAxis).contains(width), (1...maximumPixelsPerAxis).contains(height) else {
                throw MessagingFailure.invalidResponse
            }
            let pixels = width.multipliedReportingOverflow(by: height)
            guard !pixels.overflow, pixels.partialValue <= maximumPixels else {
                throw MessagingFailure.invalidResponse
            }
        default:
            throw MessagingFailure.invalidResponse
        }
    }
}

/// Nom affiché d'une pièce jointe : retiré des caractères de commande et de direction,
/// borné, jamais utilisable comme chemin. Un nom entièrement composé de ces caractères
/// n'existe pas : `nil` plutôt qu'un nom vide.
enum MessagingMediaName {
    static func sanitized(_ raw: String) -> String? {
        var kept = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where !isForbidden(scalar) { kept.append(scalar) }
        let cleaned = String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(MessagingMediaAttachment.maximumNameLength))
    }

    /// C0, DEL, C1, contrôles de direction (U+202A–202E, U+2066–2069) et séparateurs de
    /// chemin : aucun ne peut rester dans un nom transmis puis affiché.
    static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return value < 0x20
            || value == 0x7F
            || (0x80...0x9F).contains(value)
            || (0x202A...0x202E).contains(value)
            || (0x2066...0x2069).contains(value)
            || value == 0x2F
            || value == 0x5C
    }
}

/// Valeur de la clé namespacée `ch.drivy.messaging` (#97 §4.2) : `v`, `text`, `media`.
struct MessagingMediaContentV3: Codable, Sendable, Equatable {
    let v: Int
    let text: String?
    let media: MessagingMediaAttachment

    init(text: String?, media: MessagingMediaAttachment) throws {
        guard (text?.count ?? 0) <= MessagingMediaContent.maximumTextLength else {
            throw MessagingFailure.invalidResponse
        }
        self.v = MessagingMediaContent.version
        self.text = text
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .v)
        guard version == MessagingMediaContent.version else {
            throw DecodingError.dataCorruptedError(forKey: .v, in: container, debugDescription: "unknown version")
        }
        let text = try container.decodeIfPresent(String.self, forKey: .text)
        guard (text?.count ?? 0) <= MessagingMediaContent.maximumTextLength else {
            throw DecodingError.dataCorruptedError(forKey: .text, in: container, debugDescription: "caption too long")
        }
        let media = try container.decode(MessagingMediaAttachment.self, forKey: .media)
        self.v = version
        self.text = text
        self.media = media
    }

    /// Repli lisible par tout client : la légende si elle existe, sinon `Photo`, `PDF` ou `Pièce jointe`.
    var body: String {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        return media.mime.fallbackBody
    }
}

/// Contenu Matrix complet d'un message porteur de média (#97 §4.2) : écriture et lecture.
///
/// Écriture : `{"msgtype":"m.text","body":<repli>,"ch.drivy.messaging":{"v":3,"text":…,"media":…}}`.
/// Le contenu structuré ne va **jamais** dans `body`, et `body` ne contient jamais de JSON.
///
/// Cette lecture ne s'applique **qu'à un contenu Matrix authentifié** (`MessagingDecryptedContent`
/// de provenance `.matrixContent`) : elle n'est jamais appliquée à des octets de `body` legacy.
enum MessagingMediaContent {
    static let namespacedKey = "ch.drivy.messaging"
    static let messageType = "m.text"
    static let version = 3
    /// Plafond du contenu v3 encodé : la borne réellement contraignante est mesurée après chiffrement.
    static let maximumByteCount = 6_000
    static let maximumTextLength = 1_000

    /// Résultat de lecture d'un contenu reçu. `fallbackBody` couvre une version future inconnue :
    /// le client affiche le repli, jamais le JSON technique.
    enum Reading: Sendable, Equatable {
        case v3(MessagingMediaContentV3)
        case fallbackBody(String)
        case invalid
        case notNamespaced
    }

    /// Contenu à chiffrer. `mentions` reste celui du paramètre contrôlé, jamais celui du clair applicatif.
    static func messageContent(_ value: MessagingMediaContentV3, mentions: [String]?) throws -> Data {
        var namespaced: [String: Any] = ["v": value.v, "media": try jsonObject(value.media)]
        if let text = value.text { namespaced["text"] = text }
        var content: [String: Any] = ["msgtype": messageType, "body": value.body, namespacedKey: namespaced]
        if let mentions { content["m.mentions"] = ["user_ids": mentions] }
        return try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
    }

    /// Lecture d'un contenu reçu, sans lever : l'appelant décide quoi faire d'un échec fermé.
    ///
    /// La namespace n'est interprétée que sur un contenu Matrix complet (`msgtype` `m.text` et
    /// `body` lisible) : un ancien texte qui ressemble à du JSON reste du texte utilisateur.
    static func reading(_ bytes: Data) -> Reading {
        guard let decoded = try? JSONSerialization.jsonObject(with: bytes),
              let object = decoded as? [String: Any],
              let namespaced = object[namespacedKey] else { return .notNamespaced }
        let body = object["body"] as? String
        guard object["msgtype"] as? String == messageType else {
            return body.map(Reading.fallbackBody) ?? .notNamespaced
        }
        guard let body else { return .invalid }
        guard let fields = namespaced as? [String: Any], let version = fields["v"] as? Int else {
            return .fallbackBody(body)
        }
        guard version == Self.version else { return .fallbackBody(body) }
        // Version connue : toute anomalie est fermée, sans exposer le JSON ni décoder d'octets.
        guard let data = try? JSONSerialization.data(withJSONObject: fields),
              let value = try? JSONDecoder().decode(MessagingMediaContentV3.self, from: data) else {
            return .invalid
        }
        return .v3(value)
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
}

/// Capacité additive (#97) : chiffrer un contenu Matrix **structuré** déjà construit, sans faire
/// passer de JSON par le chemin texte générique (`encrypt(_:mentions:…)` reste legacy).
///
/// Consommateur futur : le coordinateur média/coffre (T2b2/T3), qui construit la valeur typée
/// puis appelle cette capacité. Aucun conformer n'est obligatoire : les implémentations existantes
/// du protocole générique restent valides.
protocol MessagingMatrixContentEncryption: Sendable {
    func encryptMatrixContent(_ content: MessagingMediaContentV3, mentions: [UUID],
                              scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext
}

/// Capacité additive (#97) : rendre la **provenance** du contenu déchiffré.
///
/// Consommateur futur : la lecture d'un média (T3) et le signalement d'un média, qui doivent
/// distinguer un `body` legacy d'un contenu Matrix structuré sans deviner sur des octets.
protocol MessagingContentProvenanceDecryption: Sendable {
    func decryptContent(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> MessagingDecryptedContent
}
