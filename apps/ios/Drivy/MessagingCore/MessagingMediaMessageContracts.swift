import Foundation

/// Intention média attachée au POST d'un message (#97, contrat §3.5).
///
/// Le serveur ne reçoit que l'identifiant d'intention et la taille déclarée : ni type MIME,
/// ni nom de fichier, ni clé, ni IV, ni hash, ni légende, ni contenu clair. L'initialisation
/// et le décodage appliquent la même borne `1…4 194 304` octets : un `Codable` synthétisé ne
/// peut pas contourner le contrôle.
struct MessagingMediaMessageIntent: Codable, Sendable, Equatable {
    static let minimumByteSize = 1
    static let maximumByteSize = 4_194_304

    let mediaID: UUID
    let byteSize: Int

    enum CodingKeys: String, CodingKey {
        case mediaID = "mediaId"
        case byteSize
    }

    init(mediaID: UUID, byteSize: Int) throws {
        guard (Self.minimumByteSize...Self.maximumByteSize).contains(byteSize) else {
            throw MessagingFailure.invalidResponse
        }
        self.mediaID = mediaID
        self.byteSize = byteSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mediaID = try container.decode(UUID.self, forKey: .mediaID)
        let byteSize = try container.decode(Int.self, forKey: .byteSize)
        try self.init(mediaID: mediaID, byteSize: byteSize)
    }
}

/// Référence serveur d'un média attaché, telle que `MessageView.media` la restitue (#97 §3.5).
///
/// `deleted` est un fait du serveur (tombstone de purge ou de suppression pour tous), jamais
/// la preuve que le destinataire a reçu le fichier. Un objet présent et invalide échoue fermé :
/// l'absence ou `null` signifie seulement « pas de média ».
struct MessagingMessageMediaReference: Codable, Sendable, Equatable {
    let mediaID: UUID
    let byteSize: Int
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case mediaID = "mediaId"
        case byteSize
        case deleted
    }

    init(mediaID: UUID, byteSize: Int, deleted: Bool) throws {
        guard (MessagingMediaMessageIntent.minimumByteSize...MessagingMediaMessageIntent.maximumByteSize)
            .contains(byteSize) else {
            throw MessagingFailure.invalidResponse
        }
        self.mediaID = mediaID
        self.byteSize = byteSize
        self.deleted = deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mediaID = try container.decode(UUID.self, forKey: .mediaID)
        let byteSize = try container.decode(Int.self, forKey: .byteSize)
        let deleted = try container.decode(Bool.self, forKey: .deleted)
        try self.init(mediaID: mediaID, byteSize: byteSize, deleted: deleted)
    }
}

/// Capacité additive du client (#97) : envoyer un message porteur d'un média déjà déposé et
/// persisté. Le futur coordinateur média l'appellera après le dépôt binaire ; aucun appel
/// automatique, aucun stockage, aucun rechiffrement et aucune activation de l'ancienne file
/// ne sont ajoutés par cette interface.
protocol MessagingMediaMessageSending: Sendable {
    func sendMedia(scope: MessagingScope, pending: MessagingPending,
                   media: MessagingMediaMessageIntent) async throws -> MessagingAcknowledgement
}
