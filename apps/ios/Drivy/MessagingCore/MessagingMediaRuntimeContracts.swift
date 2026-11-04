import Foundation

/// Intention média encore locale, telle que l'interface native la présente (#97).
///
/// Cette valeur ne porte ni clé, ni IV, ni hash, ni octets : seulement de quoi
/// afficher et piloter le geste. Le `clientMessageID` est l'identifiant stable
/// du geste ; `mediaID` l'identifiant du sceau déjà persisté.
struct MessagingMediaPendingSnapshot: Sendable, Identifiable {
    let clientMessageID: UUID
    let mediaID: UUID
    let conversationID: UUID
    let caption: String?
    let name: String
    let mime: MessagingMediaAttachment.MIME
    let byteSize: Int
    let createdAt: Date

    var id: UUID { clientMessageID }
}

/// Refus visibles du parcours média (#97). Catégories fermées, sans texte libre,
/// sans identifiant, sans nom, sans clé et sans contenu. Le mapping de
/// présentation appartient au lot UI.
enum MessagingMediaRuntimeFailure: Error, Sendable, Equatable {
    case unavailable, contextChanged, accessChanged, protectionUnavailable
    case invalidContent, invalidSize, invalidFormat, unreadable, lockedPDF
    case integrity, removed, membersChanged, alreadyInFlight, resultUnknown
}

/// Résultat d'une tentative d'envoi média.
///
/// `cleanupPending` vrai signifie que le serveur a confirmé l'attache mais que
/// l'effacement local de l'intention n'a pas pu être prouvé : le succès serveur
/// reste acquitté, il n'est pas transformé en faux échec.
enum MessagingMediaDelivery: Sendable {
    case confirmed(MessagingAcknowledgement, cleanupPending: Bool)
    case pending(MessagingMediaRuntimeFailure)
}

/// Surface gelée du parcours média (#97), consommée par l'interface native.
///
/// Toutes les méthodes sont asynchrones ; aucune valeur de suivi ne transporte
/// d'objet UIKit/PDFKit ni de clé. Aucune erreur brute ne traverse : les
/// implémentations ramènent leurs refus aux catégories ci-dessus
/// (`CancellationError` peut rester distincte).
protocol MessagingMediaRuntime: Sendable {
    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia
    func enqueue(_ prepared: MessagingPreparedMedia, clientMessageID: UUID,
                 conversationID: UUID, caption: String?, mentionPersonIDs: [UUID],
                 replyToMessageID: UUID?) async throws -> MessagingMediaPendingSnapshot
    func pending(conversationID: UUID) async throws -> [MessagingMediaPendingSnapshot]
    func send(clientMessageID: UUID) async -> MessagingMediaDelivery
    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery
    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia
    func invalidate() async
}
