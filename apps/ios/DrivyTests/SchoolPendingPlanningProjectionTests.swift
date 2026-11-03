import Foundation
import Testing
@testable import Drivy

/// Repères des demandes de planification conservées (#108) : une projection du coffre pour la seule portée courante,
/// qui ne confond jamais une création avec une leçon et ne touche à aucun compteur.
@MainActor
struct SchoolPendingPlanningProjectionTests {
    private let scope = ConfigurationFixture.scope()

    @Test func aRequestFromAnotherScopeNeverAppears() throws {
        let start = Date().addingTimeInterval(3_600)
        let ours = try command(.createLesson, requestedStart: start)
        let otherEpoch = try command(.createLesson, requestedStart: start, scope: ConfigurationFixture.scope(epoch: 2))
        let otherPerson = try command(.moveLesson, lessonID: UUID(), requestedStart: start,
            scope: SchoolCommandScope(personID: UUID(), schoolID: ConfigurationFixture.schoolID,
                membershipID: ConfigurationFixture.membershipID, accessEpoch: 1,
                apiBaseURL: ConfigurationFixture.scope().apiBaseURL))
        let otherSchool = try command(.cancelLesson, lessonID: UUID(),
            scope: SchoolCommandScope(personID: ConfigurationFixture.personID, schoolID: UUID(),
                membershipID: ConfigurationFixture.membershipID, accessEpoch: 1,
                apiBaseURL: ConfigurationFixture.scope().apiBaseURL))

        #expect(SchoolPendingPlanningProjection.markers(from: [otherEpoch], scope: scope).isEmpty)
        #expect(SchoolPendingPlanningProjection.markers(from: [otherPerson, otherSchool], scope: scope).isEmpty)
        #expect(SchoolPendingPlanningProjection.markers(from: [ours, otherEpoch, otherPerson, otherSchool], scope: scope)
            .map(\.id) == [ours.id])
    }

    @Test func onlyCreationMoveAndCancellationBecomeMarkers() throws {
        let start = Date().addingTimeInterval(3_600)
        let commands = [
            try command(.createLesson, requestedStart: start),
            try command(.moveLesson, lessonID: UUID(), requestedStart: start),
            try command(.cancelLesson, lessonID: UUID()),
            // Domaine pédagogique, mais pas une demande de planification : bilan, fin de leçon, signalement.
            try command(.completeLesson, lessonID: UUID(), requestedStart: start),
            try command(.saveReportDraft, lessonID: UUID(), requestedStart: start),
            try command(.createObservation, lessonID: UUID(), requestedStart: start),
            // Démarrage immédiat et préférences : ce ne sont pas les trois actions de la feuille de planification.
            try command(.startLessonNow, requestedStart: start),
            try command(.savePlanningDefaults, requestedStart: start),
            try command(.createInvitation, requestedStart: start)
        ]

        let markers = SchoolPendingPlanningProjection.markers(from: commands, scope: scope)
        let expectedKinds: Set<SchoolPendingPlanningMarker.Kind> = [.creation, .move, .cancellation]

        #expect(markers.count == 3)
        #expect(Set(markers.map(\.kind)) == expectedKinds)
        let unreported = Set([commands[3].id, commands[4].id, commands[5].id])
        #expect(Set(markers.map(\.id)).isDisjoint(with: unreported))
    }

    @Test func aCreationStaysProvisionalAndNeverBecomesALesson() throws {
        let creation = try command(.createLesson, requestedStart: Date().addingTimeInterval(3_600))
        let marker = try #require(SchoolPendingPlanningProjection.markers(from: [creation], scope: scope).first)

        #expect(marker.kind == .creation)
        #expect(marker.id == creation.id)
        #expect(marker.lessonID == nil)
        #expect(marker.requestedStart != nil)
        #expect(marker.title == "Planification en cours")
        // Aucune leçon ne porte ce repère : la ligne provisoire est la seule représentation possible.
        #expect(!marker.concerns(UUID()))
    }

    @Test func aMoveAndACancellationKeepTheirConfirmedLesson() throws {
        let lesson = fixtureLesson()
        let move = try command(.moveLesson, lessonID: lesson.id, requestedStart: Date().addingTimeInterval(7_200))
        let cancel = try command(.cancelLesson, lessonID: lesson.id)

        let markers = SchoolPendingPlanningProjection.markers(from: [move, cancel], scope: scope)

        #expect(markers.count == 2)
        let allConcernTheLesson = markers.allSatisfy { $0.concerns(lesson.id) }
        #expect(allConcernTheLesson)
        let moved = try #require(markers.first { $0.kind == .move })
        #expect(moved.requestedStart != nil && moved.title == "Déplacement en cours")
        let cancelled = try #require(markers.first { $0.kind == .cancellation })
        // Une annulation ne change pas l’horaire : la leçon garde ses heures, et son repère n’en invente pas.
        #expect(cancelled.requestedStart == nil && cancelled.title == "Annulation en cours")
    }

    @Test func aMarkerCountsAsNoLessonAndAsNoNextLesson() throws {
        let now = try #require(SchoolLesson.date("2026-11-03T09:00:00Z"))
        let lesson = fixtureLesson(startingIn: 3_600, now: now)
        let move = try command(.moveLesson, lessonID: lesson.id, requestedStart: now.addingTimeInterval(7_200))

        let markers = SchoolPendingPlanningProjection.markers(from: [move], scope: scope, now: now)
        #expect(markers.count == 1)

        // La leçon confirmée garde sa ligne, son état et sa place ; le repère ne fabrique ni événement ni total.
        let events = SchoolAgendaEvent.day(lessons: [lesson], courses: [], on: now, calendar: calendar)
        #expect(events.count == 1)
        let summary = SchoolAgendaEvent.summary(events, isComplete: true)
        #expect(summary.lessonCount == 1 && summary.total == 1)
        #expect(summary.spokenCount == "1 leçon")

        // La « prochaine leçon » reste la leçon de l’école, jamais une demande conservée.
        let upcoming = SchoolTodayPresentation.upcomingLessons([lesson], now: now)
        #expect(upcoming.map(\.id) == [lesson.id])
        #expect(SchoolTodayPresentation.featured(in: upcoming, now: now)?.id == lesson.id)
    }

    @Test func anUnansweredRequestIsToVerifyAndAStaleOneIsNeverInFlight() throws {
        let now = try #require(SchoolLesson.date("2026-11-03T09:00:00Z"))
        let fresh = try command(.createLesson, requestedStart: now.addingTimeInterval(3_600),
            createdAt: now.addingTimeInterval(-5))
        let waited = try command(.createLesson, requestedStart: now.addingTimeInterval(3_600),
            createdAt: now.addingTimeInterval(-600))
        let stale = try command(.moveLesson, lessonID: UUID(), requestedStart: now.addingTimeInterval(-60),
            createdAt: now.addingTimeInterval(-5))

        let markers = SchoolPendingPlanningProjection.markers(from: [fresh, waited, stale], scope: scope, now: now)
        let byID = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })

        #expect(byID[fresh.id]?.state == .inProgress && byID[fresh.id]?.title == "Planification en cours")
        // Sans réponse de l’école, le repère ne prétend plus qu’un envoi est en cours.
        #expect(byID[waited.id]?.state == .toVerify && byID[waited.id]?.title == "À vérifier")
        // Un horaire passé ne se renvoie plus : la demande reste à vérifier, jamais « en cours ».
        #expect(byID[stale.id]?.state == .toVerify && byID[stale.id]?.title == "À vérifier")
    }

    // MARK: Données synthétiques

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        return calendar
    }

    private func fixtureLesson(startingIn offset: TimeInterval = 3_600, now: Date = Date()) -> SchoolLesson {
        let start = now.addingTimeInterval(offset)
        let iso = ISO8601DateFormatter()
        return SchoolLesson(id: UUID(), schoolId: ConfigurationFixture.schoolID, version: 2,
            trainingId: HubFixture.trainingID, learnerId: HubFixture.learnerID,
            instructorMembershipId: ConfigurationFixture.membershipID,
            plannedStart: iso.string(from: start), plannedEnd: iso.string(from: start.addingTimeInterval(3_600)),
            timeZone: "Europe/Zurich", meetingPoint: "Gare nord", status: "PLANNED",
            priceCentsSnapshot: 9_000, bufferMinutesSnapshot: 10, actualStart: nil, actualEnd: nil,
            permitWarning: false, publicationVersion: 0, currentPublishedRevisionId: nil, commercialRevisionVersion: 1)
    }

    private func command(_ kind: SchoolCommandKind, lessonID: UUID? = nil, requestedStart: Date? = nil,
                         createdAt: Date = Date(), scope: SchoolCommandScope? = nil) throws -> PendingSchoolCommand {
        let id = UUID()
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["operationId": id.uuidString]
        if let requestedStart {
            body["plannedStart"] = iso.string(from: requestedStart)
            body["plannedEnd"] = iso.string(from: requestedStart.addingTimeInterval(3_600))
            body["timeZone"] = "Europe/Zurich"
        }
        let isCreation = kind == .createLesson || kind == .createObservation
        return PendingSchoolCommand(id: id, scope: scope ?? self.scope, kind: kind,
            resourceVersion: isCreation ? 0 : 3, createdAt: createdAt,
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            resourceID: lessonID, routeResourceID: kind == .createLesson ? HubFixture.trainingID : nil)
    }
}
