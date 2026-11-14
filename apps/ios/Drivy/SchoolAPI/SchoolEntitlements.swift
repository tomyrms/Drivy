import Foundation

// Droits commerciaux de l’école aux modules (R01-T03, #455) : contrat de `GET /v1/schools/{schoolId}/entitlements`
// (apps/api/src/entitlements.ts). La lecture ne contient ni offre, ni motif, ni auteur.
//
// L’app n’est jamais l’autorité : elle affiche ce que le serveur a rendu, et le serveur refuse de toute façon un usage
// nouveau d’un module non accordé (`403 MODULE_NOT_ENTITLED`). Sans lecture aboutie (hors ligne, API plus ancienne,
// école pas encore chargée), rien n’est fermé par l’affichage : un ancien état local ne retire ni n’accorde rien.
// L’historique reste lisible et les engagements en cours se terminent, quel que soit le droit.

/// Modules du catalogue commercial que l’app livre réellement. Un code inconnu de l’app reste un code inconnu :
/// il n’ouvre rien et ne ferme rien.
enum SchoolModuleCode: String, Sendable, Equatable, CaseIterable {
    case messaging = "MESSAGING"
    case collectiveCourses = "COLLECTIVE_COURSES"
}

struct SchoolEntitlements: Decodable, Sendable, Equatable {
    struct Module: Decodable, Sendable, Equatable {
        let code: String
        let entitled: Bool
    }

    /// `NOT_CONFIGURED` (aucune offre : le périmètre d’avant ce lot, rien n’est restreint) ou `OFFER_ACTIVE`. Les états
    /// commerciaux à venir (#456) restent lisibles : ils ne changent pas ce que disent les modules.
    let state: String
    let modules: [Module]
    /// Compteur de changements des droits de l’école ; sert d’`ETag` côté serveur.
    let version: Int
    /// Prochain changement programmé (une attribution qui prend effet) : au-delà, la lecture est périmée.
    let nextChangeAt: String?
    let computedAt: String

    /// Un module que la lecture ne mentionne pas n’est pas fermé par l’app : seul le serveur refuse un usage nouveau.
    func isEntitled(_ module: SchoolModuleCode) -> Bool {
        modules.first(where: { $0.code == module.rawValue })?.entitled ?? true
    }

    var nextChangeDate: Date? { nextChangeAt.flatMap { SchoolLesson.date($0) } }

    /// Forme minimale d’une réponse crédible : version positive, horodatages lisibles, aucun module en double.
    var isWellFormed: Bool {
        guard version > 0, !state.isEmpty, SchoolLesson.date(computedAt) != nil,
              Set(modules.map(\.code)).count == modules.count else { return false }
        if let nextChangeAt, SchoolLesson.date(nextChangeAt) == nil { return false }
        return true
    }
}

/// Quand relire. Une lecture n’est due que si elle n’a jamais abouti, si elle date de plus de cinq minutes, ou si
/// le changement qu’elle annonçait est arrivé à échéance.
enum SchoolEntitlementsPolicy {
    static let minimumInterval: TimeInterval = 300

    static func isDue(readAt: Date?, projection: SchoolEntitlements?, now: Date,
                      minimumInterval: TimeInterval = SchoolEntitlementsPolicy.minimumInterval) -> Bool {
        guard let readAt, let projection else { return true }
        if let change = projection.nextChangeDate, change <= now { return true }
        return now.timeIntervalSince(readAt) >= minimumInterval
    }
}

/// Lecture des droits, hors du protocole `SchoolAPI` : ses doublures de test n’ont pas à la connaître.
@MainActor
protocol SchoolEntitlementsReading: AnyObject {
    func entitlements(schoolID: UUID) async throws -> SchoolEntitlements
}
