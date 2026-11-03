import Foundation
import Testing
@testable import Drivy

/// #114 : une fin de leçon ou une absence encore dans le coffre devient un repère sur la ligne de la leçon dans
/// Aujourd’hui, et un refus définitif reçu fiche fermée reste en mémoire le temps de la rouvrir. Aucune leçon n’est
/// jamais montrée terminée sans la preuve de l’école. Personnes, leçon et réponses sont synthétiques.
@Suite(.serialized)
@MainActor
struct SchoolPendingClosureProjectionTests {
    private let scope = ConfigurationFixture.scope()

    @Test func aClosureFromAnotherScopeNeverAppears() throws {
        let lessonID = UUID()
        let ours = try command(.completeLesson, lessonID: lessonID)
        let otherEpoch = try command(.completeLesson, lessonID: lessonID, scope: ConfigurationFixture.scope(epoch: 2))
        let otherPerson = try command(.markNoShow, lessonID: lessonID,
            scope: SchoolCommandScope(personID: UUID(), schoolID: ConfigurationFixture.schoolID,
                membershipID: ConfigurationFixture.membershipID, accessEpoch: 1,
                apiBaseURL: ConfigurationFixture.scope().apiBaseURL))
        let otherSchool = try command(.markNoShow, lessonID: lessonID,
            scope: SchoolCommandScope(personID: ConfigurationFixture.personID, schoolID: UUID(),
                membershipID: ConfigurationFixture.membershipID, accessEpoch: 1,
                apiBaseURL: ConfigurationFixture.scope().apiBaseURL))

        #expect(SchoolPendingClosureProjection.markers(from: [otherEpoch], scope: scope).isEmpty)
        #expect(SchoolPendingClosureProjection.markers(from: [otherPerson, otherSchool], scope: scope).isEmpty)
        #expect(SchoolPendingClosureProjection.markers(from: [ours, otherEpoch, otherPerson, otherSchool], scope: scope)
            .map(\.id) == [ours.id])
    }

    @Test func onlyCompletionAndAbsenceBecomeMarkers() throws {
        let lessonID = UUID()
        let commands = [
            try command(.completeLesson, lessonID: lessonID),
            try command(.markNoShow, lessonID: lessonID),
            // Même domaine pédagogique, mais ni une fin ni une absence.
            try command(.createLesson, lessonID: lessonID),
            try command(.moveLesson, lessonID: lessonID),
            try command(.cancelLesson, lessonID: lessonID),
            try command(.saveReportDraft, lessonID: lessonID),
            try command(.savePreparation, lessonID: lessonID),
            try command(.startLesson, lessonID: lessonID),
            try command(.createObservation, lessonID: lessonID)
        ]

        let markers = SchoolPendingClosureProjection.markers(from: commands, scope: scope)

        #expect(markers.count == 2)
        #expect(Set(markers.map(\.kind)) == Set([.completion, .absence]))
        #expect(Set(markers.map(\.id)).isDisjoint(with: Set(commands.dropFirst(2).map(\.id))))
    }

    @Test func anUnansweredClosureIsToVerifyAndAFreshOneIsInFlight() throws {
        let now = try #require(SchoolLesson.date("2026-11-03T09:00:00Z"))
        let fresh = try command(.completeLesson, lessonID: UUID(), createdAt: now.addingTimeInterval(-5))
        let waited = try command(.markNoShow, lessonID: UUID(), createdAt: now.addingTimeInterval(-600))

        let markers = SchoolPendingClosureProjection.markers(from: [fresh, waited], scope: scope, now: now)
        let byID = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })

        #expect(byID[fresh.id]?.state == .inProgress && byID[fresh.id]?.title == "Fin en cours")
        // Sans réponse de l’école, le repère ne prétend plus qu’un envoi est en cours.
        #expect(byID[waited.id]?.state == .toVerify && byID[waited.id]?.title == "À vérifier")
    }

    @Test func aRefusalStaysInMemoryUntilTheSheetReopensOrTheScopeChanges() {
        SchoolRefusedClosureMemory.forgetAll()
        let lessonID = UUID()
        SchoolRefusedClosureMemory.remember(lessonID: lessonID, scope: scope, kind: .completion)

        let kept = SchoolRefusedClosureMemory.marker(forLesson: lessonID, scope: scope)
        #expect(kept?.title == "Fin refusée" && kept?.kind == .completion)
        // Une autre époque, une autre personne ou une autre école n’héritent jamais du refus.
        #expect(SchoolRefusedClosureMemory.markers(for: ConfigurationFixture.scope(epoch: 2)).isEmpty)
        #expect(SchoolRefusedClosureMemory.marker(forLesson: lessonID,
            scope: SchoolCommandScope(personID: UUID(), schoolID: ConfigurationFixture.schoolID,
                membershipID: ConfigurationFixture.membershipID, accessEpoch: 1,
                apiBaseURL: ConfigurationFixture.scope().apiBaseURL)) == nil)
        // Une absence refusée se dit avec ses propres mots.
        SchoolRefusedClosureMemory.remember(lessonID: UUID(), scope: scope, kind: .absence)
        #expect(Set(SchoolRefusedClosureMemory.markers(for: scope).map(\.title)) == Set(["Fin refusée", "Absence refusée"]))

        // Réouverture de la fiche : le repère a rempli son rôle.
        SchoolRefusedClosureMemory.forget(lessonID: lessonID, scope: scope)
        #expect(SchoolRefusedClosureMemory.marker(forLesson: lessonID, scope: scope) == nil)

        // Changement de portée : aucun repère d’un autre contexte ne survit.
        SchoolRefusedClosureMemory.remember(lessonID: lessonID, scope: scope, kind: .completion)
        SchoolRefusedClosureMemory.forgetAll()
        #expect(SchoolRefusedClosureMemory.markers(for: scope).isEmpty)
    }

    @Test func aRefusalReceivedAfterTheSheetWasLeftIsKeptThenForgottenOnReopening() async throws {
        SchoolRefusedClosureMemory.forgetAll()
        let server = RefusingClosureServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        let start = try #require(model.lesson?.startedAt)
        await server.hold()
        let closing = Task { await model.complete(start: start, end: start.addingTimeInterval(60), reason: "",
            localCaptureStopped: true) }
        try await HubFixture.wait { await server.isHolding() }
        #expect(model.leaveWhileClosureIsSent())
        await server.release()
        #expect(!(await closing.value))

        // Refus définitif après la fermeture : la demande a quitté le coffre et ne sera plus vérifiable. Un repère en
        // mémoire seulement reste pour Aujourd’hui.
        #expect(outbox.value == nil && outbox.removals.count == 1)
        let kept = try #require(SchoolRefusedClosureMemory.marker(forLesson: HubFixture.lessonID, scope: scope))
        #expect(kept.kind == .completion && kept.title == "Fin refusée")
        // Aucune leçon n’est montrée terminée : l’école n’a pas enregistré la fin.
        #expect(model.lesson?.status == "PLANNED")

        // Fiche rouverte : le repère a rempli son rôle, la raison se lit dans la fiche.
        let reopened = workspace(server, outbox)
        await reopened.load()
        #expect(SchoolRefusedClosureMemory.marker(forLesson: HubFixture.lessonID, scope: scope) == nil)
    }

    @Test func aRefusalWithTheSheetStillOpenIsNeverKeptInMemory() async throws {
        SchoolRefusedClosureMemory.forgetAll()
        let server = RefusingClosureServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        let start = try #require(model.lesson?.startedAt)

        #expect(!(await model.complete(start: start, end: start.addingTimeInterval(60), reason: "", localCaptureStopped: true)))
        #expect(outbox.value == nil)
        // La fiche est ouverte : le refus s’y lit, rien n’est gardé pour Aujourd’hui.
        #expect(SchoolRefusedClosureMemory.marker(forLesson: HubFixture.lessonID, scope: scope) == nil)
    }

    @Test func aLessonIsNeverShownCompletedWithoutProof() throws {
        let now = try #require(SchoolLesson.date("2026-09-28T12:10:00Z"))
        let lesson = HubFixture.lesson(permitWarning: false, actualStart: "2026-09-28T11:00:00Z")
        let command = try command(.completeLesson, lessonID: lesson.id, createdAt: now)

        let marker = try #require(SchoolPendingClosureProjection.markers(from: [command], scope: scope, now: now).first)

        // La demande conservée ne change ni le statut de la leçon ni ses mots : la preuve de l’école manque encore.
        #expect(lesson.status == "PLANNED" && lesson.statusLabel == "En cours")
        #expect(marker.title == "Fin en cours" && marker.title != lesson.statusLabel)
        #expect(marker.lessonID == lesson.id && marker.state == .inProgress)
    }

    // MARK: Données synthétiques

    private func workspace(_ server: RefusingClosureServer, _ outbox: ConfigurationOutboxStub) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership,
            lessonID: HubFixture.lessonID, client: client, outbox: outbox)
    }

    private func command(_ kind: SchoolCommandKind, lessonID: UUID? = nil,
                         createdAt: Date = Date(), scope: SchoolCommandScope? = nil) throws -> PendingSchoolCommand {
        let id = UUID()
        var body: [String: Any] = ["operationId": id.uuidString]
        if kind == .completeLesson {
            body["actualStart"] = "2026-09-28T11:00:00Z"
            body["actualEnd"] = "2026-09-28T12:00:00Z"
        }
        if kind == .markNoShow { body["reason"] = "Élève absent au rendez-vous." }
        let isCreation = kind == .createLesson || kind == .createObservation
        return PendingSchoolCommand(id: id, scope: scope ?? self.scope, kind: kind,
            resourceVersion: isCreation ? 0 : 3, createdAt: createdAt,
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            resourceID: lessonID, routeResourceID: kind == .createLesson ? HubFixture.trainingID : nil)
    }
}

/// École synthétique : la fin ou l’absence est retenue à la demande puis refusée définitivement (400 motivé).
/// La leçon reste planifiée et commencée : rien n’a été enregistré.
private actor RefusingClosureServer: SchoolHTTPTransport {
    private let fallback = HubServer()
    private var held = false, holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func hold() { held = true }
    func release() { held = false; let values = waiters; waiters = []; for item in values { item.resume() } }
    func isHolding() -> Bool { holding }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!, leaf = url.lastPathComponent.lowercased()
        func ok(_ data: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
                "serverTime": "2026-09-28T13:00:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        func refused() -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: Data("{\"code\":\"LESSON_STARTED\",\"title\":\"Refus\"}".utf8), status: 400, url: url,
                contentType: "application/problem+json")
        }
        if request.httpMethod == "POST", ["complete", "no-show"].contains(leaf) {
            if held {
                holding = true
                await withCheckedContinuation { waiters.append($0) }
                holding = false
            }
            return refused()
        }
        if request.httpMethod == "GET", leaf == HubFixture.lessonID.uuidString.lowercased() {
            let lesson = HubFixture.lesson(permitWarning: false, actualStart: "2026-09-28T11:00:00Z")
            return try ok(try JSONSerialization.jsonObject(with: JSONEncoder().encode(lesson)) as? [String: Any] ?? [:])
        }
        return try await fallback.send(request)
    }
}
