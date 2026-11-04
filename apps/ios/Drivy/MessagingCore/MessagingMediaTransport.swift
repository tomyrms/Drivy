import Foundation

/// Reçu de dépôt d'un média chiffré (#97, contrat §3.4/§4.5).
///
/// Un reçu n'atteste **que** le dépôt : `ATTACHED` signifie que le serveur connaît déjà
/// le média rattaché à un message, jamais que le destinataire l'a reçu ou publié.
/// L'état `PURGED` n'est pas représentable : une purge est un refus, pas un succès.
struct MessagingMediaReceipt: Sendable, Equatable {
    enum State: String, Sendable, Equatable {
        case uploaded = "UPLOADED"
        case attached = "ATTACHED"
    }

    /// Identifiant d'intention : celui du sceau déposé, jamais un nouvel UUID.
    let mediaID: UUID
    /// Taille du chiffré déposé, en octets.
    let byteSize: Int
    /// SHA-256 **hexadécimal minuscule** du chiffré (64 caractères), tel qu'accusé par le serveur.
    let sha256: String
    let state: State
}

/// Transport binaire des médias : dépôt, téléchargement, annulation (contrat §4.5).
///
/// Frère de `MessagingHTTPTransport` pour le corps et la réponse binaires. Aucune
/// implémentation ne doit transformer un refus en succès : sans écriture durable
/// confirmée et vérifiée, rien n'est déposé.
protocol MessagingMediaTransport: Sendable {
    func upload(_ sealed: MessagingSealedMedia, scope: MessagingScope, conversationID: UUID) async throws -> MessagingMediaReceipt
    func download(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws -> Data
    func cancel(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws
}

/// Refus utiles au futur coordinateur média (#97 §3.12, §3.11).
///
/// Chaque cas reste une erreur fermée : aucun texte libre, aucune URL, aucun identifiant,
/// aucun hash ni contenu n'est transporté par l'erreur. Cette primitive ne définit **aucun**
/// texte d'affichage : le mapping de présentation appartient au futur worker UI.
enum MessagingMediaTransportFailure: Error, Equatable, Sendable {
    /// Refusé avant réseau : taille hors 1…4 Mio, sceau incohérent, appareil invalide, origine refusée.
    case invalidIntent
    /// Le compte, l'école, l'époque ou l'origine ont changé : la réponse n'est jamais rendue.
    case contextChanged
    /// Jeton ou droits refusés (401/403 générique).
    case accessChanged
    /// 403 `MESSAGING_DEVICE_REQUIRED` : appareil absent ou révoqué.
    case deviceRequired
    /// 404 uniforme : inconnu, autre école/conversation, hors plage, masqué, supprimé ou purgé.
    case notFound
    /// 409 `MEDIA_PURGED` : identifiant déjà purgé, jamais ressuscité.
    case purged
    /// 409 `MEDIA_ALREADY_ATTACHED` : l'annulation n'est pas possible, ce n'est pas un succès.
    case alreadyAttached
    /// 409 `MEDIA_INTENT_CONFLICT` : même identifiant, autres octets.
    case intentConflict
    /// 409 `MEDIA_SIZE_MISMATCH` : taille déclarée différente de la taille stockée.
    case sizeConflict
    /// 409 sans code média connu : rien n'est acquis.
    case stateConflict
    /// Panne réseau, délai dépassé, 5xx : aucun nouvel essai automatique, même intention.
    case unavailable
    /// Enveloppe, type, statut, en-tête de contexte ou URL finale non conformes.
    case invalidResponse
    /// Le chiffré reçu ou le reçu déposé ne correspond pas au hash ou à la taille annoncés.
    case integrityMismatch
    /// Réponse ou flux au-delà du plafond borné : jamais tronquée puis acceptée.
    case tooLarge
}
