#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Une page du dossier (Leçons ou Progression) d’un élève qui suit deux ou trois permis, avec son filtre.
/// Même écran que celui que le dossier pousse : seul le contexte est synthétique et en mémoire.
struct SchoolVisualTrainingPage: View {
    let context: SchoolVisualContext
    let permitCount: Int
    let section: SchoolTrainingSection
    @State private var permit: UUID?

    var body: some View {
        SchoolTrainingScreen(client: context.client, workspace: context.workspace, learner: context.learner,
            trainingIDs: SchoolVisualData.permitTrainingIDs(count: permitCount), permit: $permit,
            section: section, showsHeading: true)
    }
}

/// Formations supplémentaires et leçon annulée du rendu de contrôle. Tout reste additif : sans demande de
/// plusieurs permis, l’élève garde sa seule formation (…005) et ses deux leçons, comme avant.
/// Aucune de ces données ne représente une personne réelle.
extension SchoolVisualData {
    nonisolated static let cancelledLessonID = identifier(340)
    nonisolated static let permitATrainingID = identifier(320)
    nonisolated static let permitBETrainingID = identifier(321)
    /// La leçon d’absence du permis A : sa ligne prouve que les leçons du second permis sont lues.
    nonisolated static let permitANoShowLessonID = identifier(341)

    /// Le nombre de permis de l’élève pour un écran de contrôle : un seul, sauf les écrans « multi » et « two ».
    nonisolated static func permitCount(for screen: String) -> Int {
        switch screen {
        case "dossier-multi", "lessons-multi", "progression-multi": 3
        case "lessons-two": 2
        default: 1
        }
    }

    /// La leçon ouverte en fiche : la planifiée, l’annulée, ou la terminée par défaut.
    nonisolated static func reportLessonID(for screen: String) -> UUID {
        switch screen {
        case "lesson-planned": plannedLessonID
        case "lesson-cancelled": cancelledLessonID
        default: lessonID
        }
    }

    /// Les formations de l’élève, dans l’ordre du dossier : la formation en cours d’abord.
    nonisolated static func permitTrainingIDs(count: Int) -> [UUID] {
        Array([trainingID, permitATrainingID, permitBETrainingID].prefix(max(1, min(count, 3))))
    }

    // MARK: - Leçon annulée

    /// Lecture de la fiche d’une leçon annulée : la leçon, ses objectifs prévus, aucun bilan.
    static func cancelledLessonObjects() -> [String: Any] {
        let root = "/v1/schools/\(schoolID.uuidString)"
        let lesson = cancelledLesson()
        let goals: [[String: Any]] = [
            ["label": "Revoir les priorités à droite", "competencyId": identifier(30).uuidString, "context": NSNull()],
            ["label": "Préparer l’insertion sur l’autoroute", "competencyId": identifier(32).uuidString, "context": NSNull()]
        ]
        let preparation: [String: Any] = ["id": identifier(370).uuidString, "schoolId": schoolID.uuidString,
            "lessonId": cancelledLessonID.uuidString, "version": 1, "goals": goals,
            "administrativeCheckNote": NSNull(), "plannedWaypoints": [] as [Any]]
        let path = "\(root)/lessons/\(cancelledLessonID.uuidString)"
        return [path: lesson, "\(path)/preparation": preparation, "\(path)/reports": permitPage([])]
    }

    private static func cancelledLesson() -> [String: Any] {
        permitLesson(cancelledLessonID, training: trainingID, start: "2026-09-24T12:00:00Z", end: "2026-09-24T12:50:00Z",
            status: "CANCELLED", place: "Gare de Cernier")
    }

    // MARK: - Plusieurs permis

    /// Remplace la formation, l’offre, le référentiel et les leçons du dossier par ceux d’un élève à `count` permis
    /// (2 ou 3), et ajoute pour chaque formation sa lecture et sa progression. Les leçons de toutes les
    /// formations sont dans une seule page : le transport les filtre par `trainingId`, comme l’école.
    static func permitObjects(count: Int, training: [String: Any], offerings: [[String: Any]],
                              curricula: [[String: Any]], lessons: [[String: Any]]) -> [String: Any] {
        let root = "/v1/schools/\(schoolID.uuidString)"
        let chosen = Array(permitSpecs().prefix(max(0, min(count, 3) - 1)))
        var trainings: [[String: Any]] = [training]
        var allOfferings = offerings
        var allCurricula = curricula
        var allLessons = lessons + [cancelledLesson(), upcomingLesson()]
        var objects: [String: Any] = [:]
        for spec in chosen {
            let item = trainingObject(spec)
            trainings.append(item)
            allOfferings.append(offeringObject(spec))
            allCurricula.append(curriculumObject(spec))
            allLessons.append(contentsOf: spec.lessons)
            objects["\(root)/trainings/\(spec.training.uuidString)"] = item
            objects["\(root)/trainings/\(spec.training.uuidString)/progress"] = progressObject(spec)
        }
        objects["\(root)/trainings"] = permitPage(trainings)
        objects["\(root)/offerings"] = permitPage(allOfferings)
        objects["\(root)/curricula"] = permitPage(allCurricula)
        objects["\(root)/lessons"] = permitPage(allLessons)
        return objects
    }

    private static func permitPage(_ items: [[String: Any]]) -> [String: Any] {
        ["items": items, "nextCursor": NSNull()]
    }

    private struct PermitCompetency {
        let key: String
        let label: String
        let text: String
    }

    private struct PermitObservation {
        let index: Int
        let level: String
        let context: String
        let day: String
    }

    private struct PermitSpec {
        let training: UUID
        let offering: UUID
        let curriculum: UUID
        let category: String
        let status: String
        let startedOn: String
        let closedOn: String?
        let offeringKey: String
        let minutes: Int
        let priceCents: Int
        /// Numéro (pour `identifier`) de la première compétence du référentiel.
        let firstCompetency: Int
        let competencies: [PermitCompetency]
        let observed: [PermitObservation]
        let sourceLesson: UUID
        let sourceRevision: UUID
        let lessons: [[String: Any]]
    }

    private static func permitSpecs() -> [PermitSpec] { [motorcycleSpec(), trailerSpec()] }

    /// Permis A, en pause : une leçon réalisée, une absence.
    private static func motorcycleSpec() -> PermitSpec {
        let competencies = [
            PermitCompetency(key: "balance", label: "Équilibre à basse vitesse", text: "Maîtriser la moto au pas, en slalom et en demi-tour."),
            PermitCompetency(key: "emergency-braking", label: "Freinage d’urgence", text: "Freiner fort en gardant la trajectoire."),
            PermitCompetency(key: "corners", label: "Trajectoires en virage", text: "Choisir l’entrée, le point de corde et la sortie."),
            PermitCompetency(key: "gaze", label: "Regard et anticipation", text: "Porter le regard loin et lire la route."),
            PermitCompetency(key: "lane-position", label: "Placement dans la circulation", text: "Occuper la voie pour voir et être vu.")
        ]
        let observed = [
            PermitObservation(index: 0, level: "GUIDED", context: "Slalom et demi-tour sur le plateau", day: "2026-09-09T16:00:00Z"),
            PermitObservation(index: 1, level: "DISCOVERING", context: "Freinage sur sol sec", day: "2026-09-09T16:00:00Z")
        ]
        let lessons = [
            permitLesson(permitANoShowLessonID, training: permitATrainingID, start: "2026-09-16T15:00:00Z",
                end: "2026-09-16T15:50:00Z", status: "NO_SHOW", place: "Place du Port, Neuchâtel", priceCents: 11000),
            permitLesson(identifier(342), training: permitATrainingID, start: "2026-09-09T15:00:00Z",
                end: "2026-09-09T15:50:00Z", status: "COMPLETED", place: "Place du Port, Neuchâtel", priceCents: 11000, done: true)
        ]
        return PermitSpec(training: permitATrainingID, offering: identifier(322), curriculum: identifier(310),
            category: "A", status: "PAUSED", startedOn: "2026-03-02", closedOn: nil,
            offeringKey: "Moto · plateau et circulation", minutes: 50, priceCents: 11000, firstCompetency: 350,
            competencies: competencies, observed: observed, sourceLesson: identifier(342), sourceRevision: identifier(347),
            lessons: lessons)
    }

    /// Permis BE, terminé : deux leçons réalisées, toutes les compétences vues.
    private static func trailerSpec() -> PermitSpec {
        let competencies = [
            PermitCompetency(key: "coupling", label: "Attelage et dételage", text: "Atteler en sécurité et contrôler les raccords."),
            PermitCompetency(key: "checks", label: "Contrôles avant le départ", text: "Feux, pression, charge et rétroviseurs."),
            PermitCompetency(key: "reversing", label: "Marche arrière avec remorque", text: "Reculer en ligne droite et en courbe."),
            PermitCompetency(key: "clearance", label: "Gabarit et trajectoires", text: "Tenir compte de la longueur et de la largeur de l’ensemble.")
        ]
        let observed = [
            PermitObservation(index: 0, level: "INDEPENDENT", context: "Attelage seul, contrôle des raccords", day: "2026-02-10T10:00:00Z"),
            PermitObservation(index: 1, level: "INDEPENDENT", context: "Contrôles complets avant le départ", day: "2026-02-10T10:00:00Z"),
            PermitObservation(index: 2, level: "GUIDED", context: "Reculer dans un quai étroit", day: "2026-02-10T10:00:00Z"),
            PermitObservation(index: 3, level: "GUIDED", context: "Giratoires avec remorque", day: "2026-01-20T10:00:00Z")
        ]
        let lessons = [
            permitLesson(identifier(343), training: permitBETrainingID, start: "2026-01-20T09:00:00Z",
                end: "2026-01-20T10:20:00Z", status: "COMPLETED", place: "Dépôt de Fontainemelon", priceCents: 14000, done: true),
            permitLesson(identifier(344), training: permitBETrainingID, start: "2026-02-10T09:00:00Z",
                end: "2026-02-10T10:20:00Z", status: "COMPLETED", place: "Dépôt de Fontainemelon", priceCents: 14000, done: true)
        ]
        return PermitSpec(training: permitBETrainingID, offering: identifier(323), curriculum: identifier(311),
            category: "BE", status: "COMPLETED", startedOn: "2025-11-10", closedOn: "2026-02-14",
            offeringKey: "Remorque · catégorie BE", minutes: 80, priceCents: 14000, firstCompetency: 360,
            competencies: competencies, observed: observed, sourceLesson: identifier(344), sourceRevision: identifier(348),
            lessons: lessons)
    }

    private static func trainingObject(_ spec: PermitSpec) -> [String: Any] {
        let closed: Any
        if let closedOn = spec.closedOn { closed = closedOn } else { closed = NSNull() }
        return ["id": spec.training.uuidString, "schoolId": schoolID.uuidString, "learnerId": learnerID.uuidString,
            "offeringId": spec.offering.uuidString, "version": 1, "categoryCode": spec.category, "status": spec.status,
            "startedOn": spec.startedOn, "closedOn": closed]
    }

    private static func offeringObject(_ spec: PermitSpec) -> [String: Any] {
        ["id": spec.offering.uuidString, "schoolId": schoolID.uuidString, "version": 1, "offeringKey": spec.offeringKey,
         "categoryCode": spec.category, "curriculumVersionId": spec.curriculum.uuidString,
         "policyVersionId": policyID.uuidString, "enabled": true,
         "defaultDurationMinutes": spec.minutes, "defaultPriceCents": spec.priceCents]
    }

    private static func curriculumObject(_ spec: PermitSpec) -> [String: Any] {
        var items: [[String: Any]] = []
        for (index, competency) in spec.competencies.enumerated() {
            let item: [String: Any] = ["id": identifier(spec.firstCompetency + index).uuidString,
                "schoolId": schoolID.uuidString, "version": 1, "curriculumVersionId": spec.curriculum.uuidString,
                "key": competency.key, "label": competency.label, "description": competency.text, "sortOrder": index]
            items.append(item)
        }
        return ["id": spec.curriculum.uuidString, "schoolId": schoolID.uuidString, "version": 1,
            "categoryCode": spec.category, "revision": 1, "approved": true, "competencies": items]
    }

    private static func progressObject(_ spec: PermitSpec) -> [String: Any] {
        var items: [[String: Any]] = []
        for seen in spec.observed {
            let item: [String: Any] = ["competencyId": identifier(spec.firstCompetency + seen.index).uuidString,
                "sourceLessonId": spec.sourceLesson.uuidString, "sourceRevisionId": spec.sourceRevision.uuidString,
                "label": spec.competencies[seen.index].label, "level": seen.level, "context": seen.context,
                "observedAt": seen.day]
            items.append(item)
        }
        let observedIndexes = Set(spec.observed.map(\.index))
        var unobserved: [String] = []
        for index in spec.competencies.indices where !observedIndexes.contains(index) {
            unobserved.append(identifier(spec.firstCompetency + index).uuidString)
        }
        return ["trainingId": spec.training.uuidString, "items": items,
            "unobservedCompetencyIds": unobserved, "computedAt": time]
    }

    // MARK: - Leçons

    /// Une leçon à venir, toujours dans le futur : après-demain, 14 h, heure de l’école.
    private static func upcomingLesson() -> [String: Any] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        let start = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day
        let end = start.addingTimeInterval(50 * 60)
        let iso = ISO8601DateFormatter()
        return permitLesson(identifier(345), training: trainingID, start: iso.string(from: start), end: iso.string(from: end),
            status: "PLANNED", place: "Place du Port, Neuchâtel")
    }

    private static func permitLesson(_ id: UUID, training: UUID, start: String, end: String, status: String,
                                     place: String, priceCents: Int = 9500, done: Bool = false) -> [String: Any] {
        let actualStart: Any
        let actualEnd: Any
        if done {
            actualStart = start
            actualEnd = end
        } else {
            actualStart = NSNull()
            actualEnd = NSNull()
        }
        return ["id": id.uuidString, "schoolId": schoolID.uuidString, "version": 1,
            "trainingId": training.uuidString, "learnerId": learnerID.uuidString,
            "instructorMembershipId": membershipID.uuidString, "plannedStart": start, "plannedEnd": end,
            "timeZone": "Europe/Zurich", "meetingPoint": place, "status": status,
            "priceCentsSnapshot": priceCents, "bufferMinutesSnapshot": 10,
            "actualStart": actualStart, "actualEnd": actualEnd, "permitWarning": false,
            "publicationVersion": 0, "currentPublishedRevisionId": NSNull(), "commercialRevisionVersion": 1]
    }
}
#endif
