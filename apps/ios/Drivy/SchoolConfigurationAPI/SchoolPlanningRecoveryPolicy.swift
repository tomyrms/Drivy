import Foundation

/// Barrière native du créneau demandé (#106, L1b) : règle pure, sans texte d’écran.
/// Seules une création et un déplacement portent un début ; l’absence ou l’illisibilité du début ferme
/// l’écriture au lieu de l’autoriser par défaut.
enum SchoolPlanningRecoveryPolicy {
    enum LessonStartAdmission: Equatable, Sendable {
        /// Commande sans début demandé : sa reprise garde son propre contrat.
        case notConcerned
        case future(Date)
        /// Début égal ou déjà passé : l’école refuserait, l’écriture ne part pas.
        case notFuture(Date)
        /// Début absent ou impossible à relire : aucune preuve d’un créneau encore admissible.
        case unreadable
    }

    static func admission(_ command: PendingSchoolCommand, at now: Date) -> LessonStartAdmission {
        guard command.kind == .createLesson || command.kind == .moveLesson else { return .notConcerned }
        guard let start = command.requestedLessonStart else { return .unreadable }
        return start > now ? .future(start) : .notFuture(start)
    }

    static func permitsWrite(_ command: PendingSchoolCommand, at now: Date) -> Bool {
        switch admission(command, at: now) {
        case .notConcerned, .future: true
        case .notFuture, .unreadable: false
        }
    }
}

/// Refus local fermé et non définitif : la demande reste dans la file avec ses octets, sa version et son
/// identifiant, et son reçu reste consultable. Aucune copie d’écran n’est portée ici.
enum SchoolPlanningWriteRefusal: Error, Equatable, Sendable {
    case lessonStartNotAdmissible
}
