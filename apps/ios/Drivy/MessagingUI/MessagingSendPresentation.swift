import Foundation

/// Projection de l'unique état de la file Drivy, commune à la bulle, aux actions et à VoiceOver (#237).
/// Aucun délai ni état réseau propre à la vue : seul l'accusé serveur peut produire la coche « envoyé ».
struct MessagingSendPresentation: Equatable, Sendable {
    let status: MessagingWorkspace.SendStatus?

    var showsSendingIndicator: Bool { status == .sending || status == .slow }

    var isAccepted: Bool {
        if case .accepted? = status { return true }
        return false
    }

    var failure: MessagingFailure? {
        if case .failed(let failure)? = status { return failure }
        return nil
    }

    var canRetry: Bool {
        switch status {
        case .uncertain?: true
        case .failed(let failure)?: failure.allowsSameSendRetry
        // « Non confirmé » après dix secondes reste la requête en vol, pas une invitation à en lancer une autre.
        default: false
        }
    }

    var label: String? {
        switch status {
        case .queued?, nil: "En attente"
        case .slow?: "Envoi…"
        case .offline?: "En attente de connexion"
        case .unconfirmed?: "Confirmation en attente"
        case .uncertain?: "Non confirmé"
        case .failed?: "Échec"
        case .sending?, .accepted?: nil
        }
    }

    var symbol: String {
        switch status {
        case .offline?: "wifi.slash"
        case .unconfirmed?, .uncertain?: "questionmark.circle"
        case .failed?: "exclamationmark.circle"
        default: "clock"
        }
    }

    var accessibilityLabel: String {
        switch status {
        case .queued?, nil: "en attente d’envoi"
        case .sending?, .slow?: "envoi en cours"
        case .offline?: "en attente de connexion"
        case .unconfirmed?: "envoi non confirmé, réponse attendue"
        case .uncertain?: "envoi non confirmé"
        case .failed?: "échec de l’envoi"
        case .accepted?: "envoyé"
        }
    }
}

extension MessagingFailure {
    /// Reprise de la même intention selon le refus reçu. Les accès, appareils et clés doivent être corrigés d'abord.
    var allowsSameSendRetry: Bool {
        switch self {
        case .unavailable, .invalidResponse, .membersChanged, .stateConflict, .mutationReceiptUnavailable: true
        default: false
        }
    }
}
