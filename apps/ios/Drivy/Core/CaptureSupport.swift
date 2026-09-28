import Foundation

/// Statut d’une observation notée pendant la leçon ; le serveur emploie ATTENTION, TO_REWORK et POSITIVE.
enum ObservationStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case attention, toWorkOn, positive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .attention: "Attention"
        case .toWorkOn: "À retravailler"
        case .positive: "Point positif"
        }
    }
}

/// État réel du GPS sur l’appareil, affiché tel quel : aucune position n’est inventée.
enum GPSStatus: Equatable, Sendable {
    case inactive, requestingPermission, waitingForPosition, recording, denied, interrupted
    var label: String {
        switch self {
        case .inactive: "Sans GPS"
        case .requestingPermission: "Autorisation GPS demandée"
        case .waitingForPosition: "En attente de position"
        case .recording: "GPS actif"
        case .denied: "GPS non autorisé"
        case .interrupted: "GPS interrompu"
        }
    }
}

/// Échecs du stockage chiffré local : jamais de repli vers du clair.
enum StorageError: Error, LocalizedError, Equatable, Sendable {
    case storageUnavailable, encryptionUnavailable

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "La sauvegarde sur cet appareil est indisponible. Les données déjà enregistrées sont conservées."
        case .encryptionUnavailable: "Le stockage chiffré n’a pas pu être vérifié. Aucune donnée ne sera enregistrée en clair."
        }
    }
}
