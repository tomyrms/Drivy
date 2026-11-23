import Foundation

/// Le mode d’ordre des signalements d’un compte : l’ordre manuel de la personne (`manual`), ou celui que le
/// service calcule d’après ses propres usages (`smart`). L’app ne calcule aucun score : elle lit une liste de clés
/// et l’applique. Le mode appartient au compte, pas à une école (R08, docs/implementation/r08-contrat-serveur-20261111.md).
enum SchoolObservationRankingMode: String, Codable, Sendable, Equatable {
    case manual = "MANUAL"
    case smart = "SMART"
}

/// Forme d’une clé de thème et d’une date de classement, telles que le contrat les définit.
enum SchoolObservationKey {
    /// `^[a-z][a-z0-9-]{0,39}$`
    static func isWellFormed(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        guard let first = bytes.first, bytes.count <= 40, (97...122).contains(first) else { return false }
        return bytes.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }

    /// `AAAA-MM-JJ`, sans interprétation : la date n’est jamais calculée par l’app.
    static func isLocalDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10 else { return false }
        for (index, byte) in bytes.enumerated() {
            if index == 4 || index == 7 {
                guard byte == 45 else { return false }
            } else {
                guard (48...57).contains(byte) else { return false }
            }
        }
        return true
    }
}
