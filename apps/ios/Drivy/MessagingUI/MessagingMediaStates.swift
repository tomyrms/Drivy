import Foundation

// États par média de la conversation (#476). Valeurs pures, sans vue : la projection du fil, les bulles et les tests
// partagent les mêmes règles. Aucun nom, légende, clé ni contenu ne sort de ces types vers un journal.

/// Où en est l'ouverture d'UNE pièce reçue. Une seule entrée par message : ouvrir une pièce ne touche jamais les autres.
enum MessagingMediaOpenState: Equatable, Sendable {
    case opening
    case failed(MessagingMediaOpenFailure)
}

/// Échec d'ouverture rendu au bon média. `canRetry` est faux quand une reprise ne peut rien changer (pièce retirée).
struct MessagingMediaOpenFailure: Equatable, Sendable {
    let message: String
    let canRetry: Bool

    init(message: String, canRetry: Bool) {
        self.message = message
        self.canRetry = canRetry
    }

    /// Libellés courts, sans nom de fichier. Une cause (hors ligne, délai) n'est jamais devinée : le runtime ne la distingue pas.
    init(_ error: Error) {
        switch error as? MessagingMediaRuntimeFailure {
        case .removed?:
            self.init(message: "Cette pièce n’est plus disponible.", canRetry: false)
        case .invalidContent?, .invalidFormat?, .integrity?, .lockedPDF?, .invalidSize?:
            self.init(message: "Pièce illisible.", canRetry: true)
        case .protectionUnavailable?:
            self.init(message: "Conservation indisponible.", canRetry: true)
        default:
            self.init(message: "Pièce indisponible.", canRetry: true)
        }
    }
}

/// Libellés VoiceOver des actions de reprise du fil (#477) : le bouton dit CE qu'il relance, pas seulement « Réessayer »,
/// puisque plusieurs pièces peuvent en porter un à l'écran. Constantes pures, testées.
enum MessagingMediaActionText {
    static let thumbnailRetry = "Réessayer l’aperçu"
    static let openRetry = "Réessayer l’ouverture"
}

/// Phase d'une intention d'envoi média projetée dans le fil.
enum MessagingMediaIntentionPhase: Hashable, Sendable {
    /// Un appel d'envoi est en cours pour cette intention (première tentative ou reprise).
    case sending
    /// Intention durable retrouvée sans tentative en cours : l'issue est inconnue, aucune réémission automatique.
    case toVerify
    /// Dernière tentative refusée ou non confirmée (`resultUnknown` reste distinct d'un échec confirmé).
    case failed(MessagingMediaRuntimeFailure)
    /// Accusé durable reçu ; le message réel n'est pas encore dans le fil. Un nettoyage local restant ne change rien.
    case confirmed(cleanupPending: Bool)
}

/// Intention projetée dans le fil : de quoi dessiner la bulle locale, sans octets ni clé.
struct MessagingMediaPendingEntry: Identifiable, Sendable {
    let snapshot: MessagingMediaPendingSnapshot
    let phase: MessagingMediaIntentionPhase
    var id: UUID { snapshot.id }
}

/// Texte, ton et reprise d'une phase. Pas de pourcentage : aucune mesure d'octets n'est raccordée.
struct MessagingMediaIntentionPresentation: Equatable, Sendable {
    enum Tone: Sendable { case neutral, warning, danger, success }

    let text: String?
    let accessibilityLabel: String
    let showsProgress: Bool
    let retryTitle: String?
    let tone: Tone

    init(_ phase: MessagingMediaIntentionPhase) {
        switch phase {
        case .sending:
            self.init(text: "Envoi…", accessibilityLabel: "envoi en cours", showsProgress: true, retryTitle: nil, tone: .neutral)
        case .toVerify:
            self.init(text: "Envoi à vérifier", accessibilityLabel: "envoi à vérifier", showsProgress: false,
                      retryTitle: "Vérifier et renvoyer", tone: .warning)
        case .failed(let failure):
            self.init(failure: failure)
        case .confirmed:
            // La coche d'envoi vient de la bulle ; aucun texte ajouté, y compris avec un nettoyage local restant.
            self.init(text: nil, accessibilityLabel: "envoyé", showsProgress: false, retryTitle: nil, tone: .success)
        }
    }

    private init(text: String?, accessibilityLabel: String, showsProgress: Bool, retryTitle: String?, tone: Tone) {
        self.text = text; self.accessibilityLabel = accessibilityLabel
        self.showsProgress = showsProgress; self.retryTitle = retryTitle; self.tone = tone
    }

    private init(failure: MessagingMediaRuntimeFailure) {
        let text = MessagingMediaComposerModel.label(failure)
        switch failure {
        case .resultUnknown, .alreadyInFlight:
            self.init(text: text, accessibilityLabel: "envoi non confirmé", showsProgress: false,
                      retryTitle: "Vérifier et renvoyer", tone: .warning)
        case .membersChanged:
            self.init(text: text, accessibilityLabel: "participants modifiés, envoi à vérifier", showsProgress: false,
                      retryTitle: "Vérifier et renvoyer aux participants", tone: .warning)
        case .contextChanged, .accessChanged:
            self.init(text: text, accessibilityLabel: "accès modifié", showsProgress: false, retryTitle: nil, tone: .danger)
        default:
            self.init(text: text, accessibilityLabel: "échec de l’envoi", showsProgress: false,
                      retryTitle: "Réessayer", tone: .danger)
        }
    }
}

/// Intention confirmée par le serveur dont le message réel n'est pas encore dans le fil.
struct MessagingMediaConfirmedIntention: Sendable {
    let snapshot: MessagingMediaPendingSnapshot
    let serverMessageID: UUID
    let cleanupPending: Bool
}
