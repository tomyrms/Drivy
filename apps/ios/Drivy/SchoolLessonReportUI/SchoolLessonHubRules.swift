import Foundation

/// Le trajet de cette leçon tel que l’appareil le connaît. Sans contrôleur de séance,
/// l’état reste inconnu : rien n’est proposé qui dépendrait du GPS de cet appareil.
enum SchoolLessonCaptureStatus: Equatable {
    case unknown, none, collecting, stopped

    @MainActor init(state: SchoolCaptureSessionController.State?, captureLessonID: UUID?, lessonID: UUID) {
        guard let state, captureLessonID == lessonID else { self = .none; return }
        switch state {
        case .preparing, .recording, .paused, .stopping: self = .collecting
        case .saved, .failed: self = .stopped
        case .idle: self = .none
        }
    }

    @MainActor init(controller: SchoolCaptureSessionController?, lessonID: UUID) {
        guard let controller else { self = .unknown; return }
        self.init(state: controller.captureID == nil ? nil : controller.state, captureLessonID: controller.lessonID, lessonID: lessonID)
    }

    /// Le constat attend l’arrêt du GPS de cette leçon.
    var permitsCompletion: Bool { self != .collecting }
}

/// Montant lu dans la fiche d’une leçon, sous le nom de ce qu’il est.
struct SchoolLessonPriceLine: Equatable, Identifiable, Sendable {
    /// `agreed` : prix convenu à la réservation. `charged` : montant retenu par l’école après la leçon.
    enum Kind: String, Sendable { case agreed, charged }
    let kind: Kind
    let title: String
    let cents: Int64
    var id: String { kind.rawValue }
}

/// Personne présentée en tête de la fiche d’une leçon, avec son rôle quand le nom seul ne le dit pas.
struct SchoolLessonHeaderIdentity: Equatable, Sendable {
    let name: String
    let role: String?
}

/// Règles de l’écran unique d’une leçon. Toutes sont relues par le serveur ;
/// elles évitent seulement de proposer une action qu’il refuserait à coup sûr.
enum SchoolLessonHubRules {
    /// L’équipe lit en tête le nom de l’élève. L’élève qui ouvre sa propre leçon connaît le sien : c’est son
    /// moniteur qui l’informe. Un compte seulement élève n’affiche donc jamais son nom, même avant la lecture
    /// (aucun titre ne change sous les yeux) ; sans nom de moniteur fourni par l’école, rien n’est affiché ni deviné.
    static func headerIdentity(learnerName: String, instructorName: String?, isOwnLearner: Bool,
                               roles: [String]) -> SchoolLessonHeaderIdentity? {
        guard isOwnLearner || (roles.contains("LEARNER") && !mayManage(roles)) else {
            return SchoolLessonHeaderIdentity(name: learnerName, role: nil)
        }
        return instructorName.map { SchoolLessonHeaderIdentity(name: $0, role: "Moniteur") }
    }

    /// Écart, en secondes, à partir duquel l’horaire réel d’une leçon terminée se lit à part de l’horaire prévu.
    static let actualScheduleThreshold: TimeInterval = 300

    /// « Horaire réel : 14:10 – 15:05 » pour une leçon terminée dont le début ou la fin s’écarte d’au moins
    /// cinq minutes de l’horaire prévu. En dessous, l’horaire prévu suffit et rien n’est ajouté.
    static func actualSchedule(_ lesson: SchoolLesson) -> String? {
        guard lesson.status == "COMPLETED", let plannedStart = lesson.startsAt, let plannedEnd = lesson.endsAt,
              let start = lesson.actualStart.flatMap(SchoolLesson.date), let end = lesson.actualEnd.flatMap(SchoolLesson.date), end > start,
              abs(start.timeIntervalSince(plannedStart)) >= actualScheduleThreshold
                || abs(end.timeIntervalSince(plannedEnd)) >= actualScheduleThreshold else { return nil }
        return "Horaire réel\u{00A0}: \(time(start, zone: lesson.timeZone))\u{00A0}–\u{00A0}\(time(end, zone: lesson.timeZone))"
    }

    /// L’équipe qui ouvre la leçon d’un collègue lit qui la donne : la fiche d’une leçon dont on n’est pas le
    /// moniteur ne montre ni ses objectifs ni ses observations, que l’école réserve à ce moniteur.
    static func instructorLine(instructorName: String?, isAuthor: Bool, isOwnLearner: Bool, roles: [String]) -> String? {
        guard !isAuthor, !isOwnLearner, mayManage(roles), let instructorName else { return nil }
        return "Moniteur\u{00A0}: \(instructorName)"
    }

    /// Bilan absent d’une leçon terminée, pour qui ne l’écrit pas. L’élève attend celui de son moniteur ;
    /// l’équipe ne lit que le bilan partagé.
    static func missingReportText(isOwnLearner: Bool) -> String {
        isOwnLearner ? "Ton moniteur n’a pas encore écrit le bilan." : "Aucun bilan partagé."
    }

    /// Le prix d’une leçon planifiée ou réalisée : une ligne. L’école n’enregistre aucun paiement, donc rien ne
    /// s’intitule « à payer » ; le compte d’une leçon réalisée porte le prix convenu et ne se relit à part que
    /// si l’école l’a corrigé. Une leçon annulée ou manquée n’affiche aucun prix : rien n’y est retenu.
    static func priceLines(lesson: SchoolLesson, account: SchoolLessonAccount?) -> [SchoolLessonPriceLine] {
        guard lesson.status == "PLANNED" || lesson.status == "COMPLETED" else { return [] }
        let agreed = lesson.priceCentsSnapshot
        guard lesson.status == "COMPLETED", let charged = account?.chargeCents, charged != agreed else {
            return [SchoolLessonPriceLine(kind: .agreed, title: "Prix de la leçon", cents: agreed)]
        }
        return [SchoolLessonPriceLine(kind: .agreed, title: "Prix à la réservation", cents: agreed),
                SchoolLessonPriceLine(kind: .charged, title: "Prix de la leçon", cents: charged)]
    }

    /// Même critère que le serveur (`syncSharedReport`) : sans texte ni niveau, rien n’est montré à l’élève
    /// et un bilan déjà partagé est retiré.
    static func reportIsEmpty(workedOn: String, observationText: String, nextStep: String,
                              observations: [SchoolReportObservation]) -> Bool {
        observations.isEmpty
            && (workedOn + observationText + nextStep).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Libellé du bouton du bilan : ce qui est enregistré, et qui le lira. L’enregistrement devient aussitôt
    /// la version lue par l’élève, sauf bilan gardé pour soi. `shared` vaut `nil` quand le réglage de partage
    /// n’a pas pu être lu : le libellé ne promet alors rien.
    static func saveReportTitle(isEmpty: Bool, shared: Bool?) -> String {
        if isEmpty { return "Enregistrer sans bilan" }
        guard let shared else { return "Enregistrer le bilan" }
        return shared ? "Enregistrer et partager le bilan" : "Enregistrer le bilan pour moi"
    }

    /// Avant un départ confirmé, compatibilité GPS à 30 minutes près du créneau ; ensuite la leçon fait foi.
    static func withinCaptureWindow(_ lesson: SchoolLesson, now: Date) -> Bool {
        if lesson.hasStarted { return true }
        guard let start = lesson.startsAt, let end = lesson.endsAt else { return false }
        return now >= start.addingTimeInterval(-1_800) && now < end.addingTimeInterval(1_800)
    }

    static func mayStartCapture(lesson: SchoolLesson, isAuthor: Bool, school: SchoolDetails?,
                                capture: SchoolLessonCaptureStatus, controllerCanPrepare: Bool, now: Date) -> Bool {
        guard isAuthor, lesson.status == "PLANNED", let school, school.id == lesson.schoolId,
              school.status == "ACTIVE", school.modules.gpsEnabled else { return false }
        return capture == .none && controllerCanPrepare && withinCaptureWindow(lesson, now: now)
    }

    /// Le démarrage confirmé ouvre la fin, indépendamment de l’horaire prévu.
    static func mayFinish(_ lesson: SchoolLesson, now: Date) -> Bool {
        lesson.status == "PLANNED" && lesson.hasStarted
    }
    /// Constat d’une observation : son statut, ou celui du repère posé d’une tuile pendant le trajet.
    static func status(of observation: SchoolObservation) -> SchoolObservationStatus? {
        if let status = observation.eventStatus.flatMap(SchoolObservationStatus.init(rawValue:)) { return status }
        return observation.isMarker ? SchoolObservationStatus(markerText: observation.text) : nil
    }

    static func mayManage(_ roles: [String]) -> Bool { roles.contains("ADMIN") || roles.contains("INSTRUCTOR") }
    static func mayMove(_ lesson: SchoolLesson, roles: [String], now: Date) -> Bool {
        mayManage(roles) && lesson.status == "PLANNED" && !lesson.hasStarted
    }
    static func mayCancel(_ lesson: SchoolLesson, roles: [String]) -> Bool {
        mayManage(roles) && lesson.status == "PLANNED"
    }

    /// Départ durable de la leçon et instant du geste de fin. Le GPS facultatif ne réduit pas la séance.
    /// Compatibilité de lecture des anciennes leçons : trajet puis horaire prévu.
    static func completionTimes(lesson: SchoolLesson, captures: [SchoolCaptureSession], now: Date) -> (start: Date, end: Date) {
        if let start = lesson.startedAt { return (start, now) }
        let own = captures.filter { $0.lessonId == lesson.id }
        let capturedStart = own.compactMap { SchoolLesson.date($0.authorizedAt) }.min()
        let capturedEnd = own.compactMap { capture -> Date? in
            if let value = capture.stoppedAt ?? capture.cutoffAt { return SchoolLesson.date(value) }
            let expiry = SchoolLesson.date(capture.expiresAt)
            return capture.captureState == .authorized ? min(now, expiry ?? now) : expiry
        }.max()
        let end = min(capturedEnd ?? lesson.endsAt ?? now, now)
        let start = min(capturedStart ?? lesson.startsAt ?? end.addingTimeInterval(-3_000), end.addingTimeInterval(-60))
        return (start, end)
    }

    /// Situation proposée pour une compétence notée : le jour et le lieu de la leçon, modifiables.
    /// Proposition modifiable et facultative, limitée à 500 caractères.
    static func observationContext(for lesson: SchoolLesson) -> String {
        let date = lesson.actualStart.flatMap(SchoolLesson.date) ?? lesson.startsAt
        let day = date.map { format($0, zone: lesson.timeZone, template: "dMMMM") } ?? ""
        let place = lesson.meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = [day.isEmpty ? "Leçon" : "Leçon du \(day)", place].filter { !$0.isEmpty }.joined(separator: " · ")
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(500)))
    }

    /// Choisir un niveau ajoute la compétence avec sa situation proposée ; « Non observé » la retire.
    /// Une situation déjà écrite n’est jamais remplacée.
    static func observations(_ values: [SchoolReportObservation], setting level: String, for competencyID: UUID,
                             context: String) -> [SchoolReportObservation] {
        var result = values
        if level.isEmpty {
            result.removeAll { $0.competencyId == competencyID }
        } else if let index = result.firstIndex(where: { $0.competencyId == competencyID }) {
            result[index].level = level
            if result[index].context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result[index].context = context }
        } else {
            result.append(SchoolReportObservation(competencyId: competencyID, level: level, context: context))
        }
        return result
    }

    /// Choix « inchangé » d’une compétence dans le bilan : la valeur vide n’écrit aucune observation. Quand l’élève a déjà un niveau
    /// issu d’une autre leçon, il est rappelé ici comme point de départ ; il n’est jamais recopié dans le bilan de cette leçon
    /// (« pas encore vu » n’est pas une note, et un niveau non travaillé ce jour-là n’est pas une observation).
    /// Si le niveau actuel vient de cette leçon même (bilan déjà enregistré), le choix vide le retire : la progression retombe alors
    /// sur le niveau d’avant, que cet écran ne connaît pas, d’où « Avant cette leçon ».
    static func unchangedChoiceLabel(current: SchoolReportProgressItem?, lessonID: UUID? = nil) -> String {
        guard let current else { return "Pas encore vu" }
        if let lessonID, current.sourceLessonId == lessonID { return "Avant cette leçon" }
        return "Actuel : \(current.levelLabel)"
    }

    /// Un niveau écrit dans un bilan gardé pour soi ne compte dans la progression qu’une fois le bilan partagé.
    static func levelIsHeldBack(chosen: Bool, reportShared: Bool) -> Bool { chosen && !reportShared }

    /// Texte d’une observation repris comme situation d’une compétence (500 caractères au plus).
    static func situation(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(500)))
    }

    /// Les observations restent des éléments distincts : les recopier dans le texte partagé rendrait
    /// leur action « Pour moi » inopérante sur cette copie. Les objectifs alimentent seulement le travail réalisé.
    static func completionReport(goals: [SchoolLessonGoal], observations: [SchoolObservation],
                                 competencies: [SchoolCatalogCompetency]) -> (workedOn: String, observationText: String) {
        let worked = goals.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return (limited(worked, 4_000), "")
    }
    private static func limited(_ text: String, _ count: Int) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix(count)))
    }

    /// « Lundi 28 septembre · 14:00 – 15:00 », dans le fuseau de la leçon.
    static func schedule(_ lesson: SchoolLesson) -> String? {
        guard let start = lesson.startsAt, let end = lesson.endsAt else { return nil }
        let day = format(start, zone: lesson.timeZone, template: "EEEEdMMMM")
        return "\(day.prefix(1).uppercased() + day.dropFirst()) · \(time(start, zone: lesson.timeZone)) – \(time(end, zone: lesson.timeZone))"
    }

    private static func time(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private static func format(_ date: Date, zone: String, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// Une relecture ne perd jamais la saisie ni ne la rebascule silencieusement sur une version concurrente.
/// Un contenu confirmé égal à la saisie est l'acquittement de notre enregistrement.
enum SchoolLessonRefreshPolicy: Equatable {
    case replace, keepEdits, conflict

    static func decide<Value: Equatable>(previous: Value?, edited: Value, received: Value?, discardingEdits: Bool) -> Self {
        guard !discardingEdits, let previous, previous != edited else { return .replace }
        if received == edited { return .replace }
        if received == previous { return .keepEdits }
        return .conflict
    }
}
