import Foundation

/// Domaines vérifiés sur les contrats actuels. Les actions sensibles restent une barrière scolaire.
/// Le domaine pédagogique ne se sérialise plus par son nom : `blocksQueueEntry` compare l'agrégat réel de deux
/// commandes d'enseignement (leçon, examen, formation, occupation) au lieu de fermer tout le domaine (#106, tâche 4).
enum SchoolCommandDomain: Equatable, Sendable {
    case school, invitations, teaching, planningPreferences

    func conflicts(with other: Self) -> Bool { self == .school || other == .school || self == other }
}

extension SchoolCommandKind {
    var schedulingDomain: SchoolCommandDomain {
        if self == .savePlanningDefaults { return .planningPreferences }
        if isInvitation { return .invitations }
        if isPlanning || isReport || isObservation || isExam || isCourse { return .teaching }
        // Configuration, contrats, catalogue, profils et droits peuvent partager la version de l'école
        // ou modifier les prérequis des autres commandes. Aucun parallélisme supposé entre ces écritures.
        return .school
    }
}

/// Ce qu'une commande d'enseignement lit ou écrit réellement côté API (#106, tâche 4). Chaque clé vient de
/// `apps/api/src` : la version d'une leçon, d'un examen, la liste d'examens d'une formation, les contrôles de permis
/// d'une formation, le souhait d'une formation, et l'occupation d'agenda qu'une route prend.
///
/// Deux commandes d'enseignement n'attendent ensemble que si leurs empreintes sont **connues** et disjointes sur toutes
/// les clés : même leçon, même examen, même formation relue, ou même occupation restent séquentiels. Une clé que la
/// file ne peut pas nommer (leçon d'un brouillon, moniteur d'une occupation) bloque la paire, comme avant.
struct SchoolTeachingFootprint: Equatable, Sendable {
    /// Clé d'agrégat : absente, nommée, ou relue par l'API sans que la file porte son identifiant.
    enum Key: Equatable, Sendable {
        case none
        case known(UUID)
        case unknown

        /// Deux clés se croisent quand elles nomment le même agrégat, ou quand l'une des deux ne peut pas être nommée.
        func overlaps(_ other: Key) -> Bool {
            switch (self, other) {
            case (.none, _), (_, .none): return false
            case let (.known(mine), .known(theirs)): return mine == theirs
            case (.unknown, _), (_, .unknown): return true
            }
        }
    }

    /// État de la leçon qu'exige la route : une leçon planifiée n'est jamais la leçon réalisée d'un brouillon.
    enum Stage: Equatable, Sendable { case any, planned, completed }

    /// Leçon dont la version est vérifiée ou avancée.
    var lesson: Key = .none
    var stage: Stage = .any
    /// Examen dont la version est vérifiée ou avancée.
    var exam: Key = .none
    /// Épreuves prévues d'une formation : la création et le report y écrivent, et l'unicité s'y vérifie.
    var examTraining: Key = .none
    /// Contrôles de permis de la formation, lus par la fin de leçon (`lesson-reports.ts:163`) sans que la file nomme sa
    /// formation : deux lectures ne se croisent pas, une lecture et une écriture si.
    var permitRead: Key = .none
    /// Contrôles de permis écrits et versionnés par le contrôle lui-même (`permits.ts:69-82`).
    var permitWrite: Key = .none
    /// Souhait de l'élève, une ligne par formation.
    var wishTraining: Key = .none
    /// Prend une occupation d'agenda future. Le moniteur et l'élève ne sont pas dans la file : deux prises sont donc
    /// réputées concurrentes. Une libération n'en est pas une, elle ne crée aucune occupation future.
    var takesSlot = false

    func conflicts(with other: Self) -> Bool {
        if sharesLesson(with: other) { return true }
        if exam.overlaps(other.exam) { return true }
        if examTraining.overlaps(other.examTraining) { return true }
        if permitRead.overlaps(other.permitWrite) || permitWrite.overlaps(other.permitRead)
            || permitWrite.overlaps(other.permitWrite) { return true }
        if wishTraining.overlaps(other.wishTraining) { return true }
        return takesSlot && other.takesSlot
    }

    private func sharesLesson(with other: Self) -> Bool {
        guard lesson.overlaps(other.lesson) else { return false }
        // Un déplacement, une préparation ou un constat exigent une leçon planifiée ; un brouillon ou une publication,
        // une leçon réalisée (`lessons.ts:390`, `lesson-reports.ts:138,159` contre `lesson-reports.ts:197,210`).
        if stage != .any, other.stage != .any, stage != other.stage { return false }
        return true
    }
}

extension PendingSchoolCommand {
    /// Empreinte réelle de la commande sur les agrégats de l'enseignement, tirée de `apps/api/src` (#106, tâche 4).
    /// `nil` quand la preuve manque, ou quand l'identifiant que la règle exige n'est pas dans la commande : la paire
    /// reste alors séquentielle, exactement comme avant.
    var teachingFootprint: SchoolTeachingFootprint? {
        switch kind {
        case .createLesson, .startLessonNow:
            // `lessons.ts:316-327` et `:333-361` insèrent une leçon neuve et ses occupations (`:149-153`) pour un
            // moniteur et un élève que la file ne porte pas. Aucune version n'est lue.
            return SchoolTeachingFootprint(takesSlot: true)
        case .moveLesson:
            // `lessons.ts:390` vérifie `drivy.lesson.version`, `:401-405` réécrit les occupations.
            guard let target = resourceID else { return nil }
            return SchoolTeachingFootprint(lesson: .known(target), stage: .planned, takesSlot: true)
        case .cancelLesson:
            // `lessons.ts:414` vérifie `drivy.lesson.version`, `:422` libère les occupations futures.
            guard let target = resourceID else { return nil }
            return SchoolTeachingFootprint(lesson: .known(target), stage: .planned)
        case .completeLesson:
            // `lesson-reports.ts:158` vérifie `drivy.lesson.version`, `:163` lit l'avertissement de permis de la
            // formation, `:174` libère les occupations.
            guard let target = resourceID else { return nil }
            return SchoolTeachingFootprint(lesson: .known(target), stage: .planned, permitRead: .unknown)
        case .markNoShow:
            // `lesson-outcomes.ts:73-74` vérifie `drivy.lesson.version`, `:78` libère les occupations.
            guard let target = resourceID else { return nil }
            return SchoolTeachingFootprint(lesson: .known(target), stage: .planned)
        case .startLesson:
            // `lessons.ts:368-370` vérifie `drivy.lesson.version` sur une leçon planifiée.
            guard let target = resourceID else { return nil }
            return SchoolTeachingFootprint(lesson: .known(target), stage: .planned)
        case .savePreparation:
            // `lesson-reports.ts:137-138` vérifie `drivy.lesson_preparation.version` sur une leçon planifiée.
            guard let target = routeResourceID else { return nil }
            return SchoolTeachingFootprint(lesson: .known(target), stage: .planned)
        case .updateLessonSharing:
            // `sharing.ts:48` vérifie `drivy.lesson.sharing_version`, sans condition d'état.
            guard let target = resourceID else { return nil }
            return SchoolTeachingFootprint(lesson: .known(target))
        case .createObservation, .updateObservation, .removeObservation:
            // `capture-observations.ts:143-164`, `:169`, `:188` : la leçon de la route, son brouillon et son
            // observation, sur une leçon planifiée ou réalisée (`:35`).
            guard let target = routeResourceID else { return nil }
            return SchoolTeachingFootprint(lesson: .known(target))
        case .saveReportDraft, .publishReportDraft:
            // `lesson-reports.ts:196` et `:209` vérifient `drivy.report_draft.version` sur une leçon réalisée ; la
            // leçon se lit par le brouillon, que la file ne relie pas à elle (seul `report_drafts/:draftId` est su).
            return SchoolTeachingFootprint(lesson: .unknown, stage: .completed)
        case .recordPermitCheck:
            // `permits.ts:69-72` vérifie `drivy.training.version` et `:82` l'avance.
            guard let training = routeResourceID else { return nil }
            return SchoolTeachingFootprint(permitWrite: .known(training))
        case .saveWish:
            // `lesson-reports.ts:148` vérifie `drivy.training_wish.version` de la formation ; aucune version de leçon.
            guard let training = routeResourceID else { return nil }
            return SchoolTeachingFootprint(wishTraining: .known(training))
        case .createExam:
            // `exams.ts:189` relit les épreuves prévues de la formation (une date prévue par type) et `:195` réserve
            // l'accompagnement du moniteur.
            guard let training = routeResourceID else { return nil }
            return SchoolTeachingFootprint(examTraining: .known(training), takesSlot: true)
        case .updateExam:
            // `exams.ts:206` vérifie `drivy.exam.version`, `:209-212` remplace l'accompagnement. Aucune épreuve
            // prévue n'est créée ni retirée : la liste de la formation ne change pas.
            guard let exam = resourceID else { return nil }
            return SchoolTeachingFootprint(exam: .known(exam), takesSlot: true)
        case .postponeExam:
            // `exams.ts:222` vérifie `drivy.exam.version`, `:227-232` ouvre une nouvelle épreuve prévue de la
            // formation et réserve l'accompagnement.
            guard let exam = resourceID, let training = routeResourceID else { return nil }
            return SchoolTeachingFootprint(exam: .known(exam), examTraining: .known(training), takesSlot: true)
        case .setExamResult:
            // `exams.ts:243` vérifie `drivy.exam.version` et `:248` sort l'épreuve des épreuves prévues de la formation.
            guard let exam = resourceID, let training = routeResourceID else { return nil }
            return SchoolTeachingFootprint(exam: .known(exam), examTraining: .known(training))
        default:
            // Tarifs, conditions commerciales, disponibilités et fermetures relisent le catalogue et les ouvertures
            // que toute écriture de leçon revalide (`lessons.ts:102-114`, `lesson-setup.ts:35-48`, `:163-171`) ;
            // l'identifiant qui les distingue (produit, moniteur) reste dans le corps, hors de la file.
            return nil
        }
    }
}

extension PendingSchoolCommand {
    func conflicts(with other: Self) -> Bool {
        if id == other.id { return true }
        guard scope.belongsToWorkspace(other.scope) else { return false }
        // Corrections et retraits de deux observations d'une même leçon (#112) : deux demandes indépendantes, même d'une époque d'accès
        // à l'autre. Deux demandes sur la même observation restent ordonnées : la seconde attend la réponse de la première.
        if kind.isObservationCorrection && other.kind.isObservationCorrection
            && routeResourceID != nil && routeResourceID == other.routeResourceID && resourceID != other.resourceID { return false }
        // Gestes de cours (#126, #128 à #130) : un par élève et par séance, indépendants les uns des autres, y compris d'une époque
        // d'accès à l'autre ; leur coffre ne contient rien d'autre.
        if kind.isCourse && other.kind.isCourse { return false }
        // Une commande d'une ancienne époque reste à résoudre avant toute autre émission dans cette école.
        guard scope == other.scope else { return true }
        // Signalements d'une même leçon (#112) : créations indépendantes, envoyées dans l'ordre des gestes par leur
        // enregistreur. Ils restent une barrière pour tout le reste du domaine pédagogique, fin de leçon comprise.
        if queuesWithObservation(other) { return false }
        return kind.schedulingDomain.conflicts(with: other.kind.schedulingDomain)
    }

    func queuesWithObservation(_ other: Self) -> Bool {
        kind == .createObservation && other.kind == .createObservation && scope == other.scope
            && routeResourceID != nil && routeResourceID == other.routeResourceID
    }
}

extension SchoolCommandOutbox {
    /// Les doubles anciens conservent leur contrat à une intention ; le coffre réel expose toute sa file.
    func pendingCommands(for scope: SchoolCommandScope) throws -> [PendingSchoolCommand] {
        try pending(for: scope).map { [$0] } ?? []
    }

    func pending(for scope: SchoolCommandScope, domain: SchoolCommandDomain) throws -> PendingSchoolCommand? {
        try pendingCommands(for: scope).first {
            $0.scope != scope || $0.kind.schedulingDomain.conflicts(with: domain)
        }
    }
}
