import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolLessonHubTests {
    // MARK: Trajet de la leçon

    @Test func captureStatusFollowsOnlyThisLessonsCapture() {
        let lesson = HubFixture.lessonID, other = UUID()
        #expect(SchoolLessonCaptureStatus(controller: nil, lessonID: lesson) == .unknown)
        #expect(SchoolLessonCaptureStatus(state: nil, captureLessonID: nil, lessonID: lesson) == .none)
        #expect(SchoolLessonCaptureStatus(state: .recording, captureLessonID: other, lessonID: lesson) == .none)
        for state in [SchoolCaptureSessionController.State.preparing, .recording, .paused, .stopping] {
            let status = SchoolLessonCaptureStatus(state: state, captureLessonID: lesson, lessonID: lesson)
            #expect(status == .collecting)
            #expect(!status.permitsCompletion)
        }
        #expect(SchoolLessonCaptureStatus(state: .saved, captureLessonID: lesson, lessonID: lesson) == .stopped)
        #expect(SchoolLessonCaptureStatus(state: .failed, captureLessonID: lesson, lessonID: lesson).permitsCompletion)
        #expect(SchoolLessonCaptureStatus(controller: SchoolCaptureSessionController(), lessonID: lesson) == .none)
    }

    @Test func startIsOfferedOnlyWhereTheServerWouldAcceptIt() {
        let start = HubFixture.date("2026-09-28T12:00:00Z"), lesson = HubFixture.lesson()
        let school = HubFixture.school(gps: true)
        func may(_ now: Date, author: Bool = true, school: SchoolDetails? = school, capture: SchoolLessonCaptureStatus = .none,
                 canPrepare: Bool = true, lesson: SchoolLesson = lesson) -> Bool {
            SchoolLessonHubRules.mayStartCapture(lesson: lesson, isAuthor: author, school: school, capture: capture,
                controllerCanPrepare: canPrepare, now: now)
        }
        #expect(may(start))
        #expect(may(start.addingTimeInterval(-1_800)))
        #expect(!may(start.addingTimeInterval(-1_801)))
        #expect(may(start.addingTimeInterval(3_000 + 1_799)))
        #expect(!may(start.addingTimeInterval(3_000 + 1_800)))
        #expect(!may(start, author: false))
        #expect(!may(start, school: HubFixture.school(gps: false)))
        #expect(!may(start, school: nil))
        #expect(!may(start, capture: .unknown))
        #expect(!may(start, capture: .collecting))
        #expect(!may(start, capture: .stopped))
        #expect(!may(start, canPrepare: false))
        #expect(!may(start, lesson: HubFixture.lesson(status: "COMPLETED")))
    }

    @Test func movingAndCancellingStayWithStaffOnPlannedLessons() {
        let lesson = HubFixture.lesson(), before = HubFixture.date("2026-09-28T11:00:00Z"), after = HubFixture.date("2026-09-28T12:30:00Z")
        #expect(SchoolLessonHubRules.mayMove(lesson, roles: ["INSTRUCTOR"], now: before))
        #expect(!SchoolLessonHubRules.mayMove(lesson, roles: ["INSTRUCTOR"], now: after))
        #expect(SchoolLessonHubRules.mayCancel(lesson, roles: ["ADMIN"]))
        #expect(!SchoolLessonHubRules.mayCancel(lesson, roles: ["LEARNER"]))
        #expect(!SchoolLessonHubRules.mayCancel(HubFixture.lesson(status: "CANCELLED"), roles: ["ADMIN"]))
    }

    // MARK: Constat

    @Test func completionUsesPlannedTimesWithoutEverProposingAFutureEnd() {
        let lesson = HubFixture.lesson()
        let over = SchoolLessonHubRules.completionTimes(lesson: lesson, captures: [], now: HubFixture.date("2026-09-28T15:00:00Z"))
        #expect(over.start == HubFixture.date("2026-09-28T12:00:00Z") && over.end == HubFixture.date("2026-09-28T12:50:00Z"))
        let during = SchoolLessonHubRules.completionTimes(lesson: lesson, captures: [], now: HubFixture.date("2026-09-28T12:20:00Z"))
        #expect(during.start == HubFixture.date("2026-09-28T12:00:00Z") && during.end == HubFixture.date("2026-09-28T12:20:00Z"))
        let early = SchoolLessonHubRules.completionTimes(lesson: lesson, captures: [], now: HubFixture.date("2026-09-28T11:00:00Z"))
        #expect(early.end == HubFixture.date("2026-09-28T11:00:00Z") && early.start < early.end)
    }

    @Test func completionPrefersTheRecordedTripTimes() {
        let lesson = HubFixture.lesson(), now = HubFixture.date("2026-09-28T13:30:00Z")
        let stopped = HubFixture.capture(authorizedAt: "2026-09-28T12:07:00Z", stoppedAt: "2026-09-28T13:02:00Z", state: .stopped)
        let times = SchoolLessonHubRules.completionTimes(lesson: lesson, captures: [stopped], now: now)
        #expect(times.start == HubFixture.date("2026-09-28T12:07:00Z") && times.end == HubFixture.date("2026-09-28T13:02:00Z"))
        // Arrêt local pas encore transmis : l’école voit encore une capture autorisée.
        let open = HubFixture.capture(authorizedAt: "2026-09-28T12:05:00Z", stoppedAt: nil, state: .authorized)
        let local = SchoolLessonHubRules.completionTimes(lesson: lesson, captures: [open], now: now)
        #expect(local.start == HubFixture.date("2026-09-28T12:05:00Z") && local.end == now)
        let foreign = HubFixture.capture(authorizedAt: "2026-09-28T10:00:00Z", stoppedAt: "2026-09-28T10:30:00Z", state: .stopped, lesson: UUID())
        #expect(SchoolLessonHubRules.completionTimes(lesson: lesson, captures: [foreign], now: now).start == HubFixture.date("2026-09-28T12:00:00Z"))
    }

    // MARK: Compétences

    @Test func choosingALevelProposesTheSituationAndNeverOverwritesWrittenText() {
        let competency = UUID(), lesson = HubFixture.lesson(meetingPoint: "Gare de Lausanne")
        let context = SchoolLessonHubRules.observationContext(for: lesson)
        #expect(context.contains("Gare de Lausanne") && context.hasPrefix("Leçon du 28"))
        var values = SchoolLessonHubRules.observations([], setting: "GUIDED", for: competency, context: context)
        #expect(values == [SchoolReportObservation(competencyId: competency, level: "GUIDED", context: context)])
        values[0].context = "Giratoire de la Maladière"
        values = SchoolLessonHubRules.observations(values, setting: "INDEPENDENT", for: competency, context: context)
        #expect(values.first?.level == "INDEPENDENT" && values.first?.context == "Giratoire de la Maladière")
        values[0].context = "  "
        values = SchoolLessonHubRules.observations(values, setting: "GUIDED", for: competency, context: context)
        #expect(values.first?.context == context)
        #expect(SchoolLessonHubRules.observations(values, setting: "", for: competency, context: context).isEmpty)
        let long = SchoolLessonHubRules.observationContext(for: HubFixture.lesson(meetingPoint: String(repeating: "é", count: 900)))
        #expect(long.unicodeScalars.count == 500)
    }

    @Test func scheduleShowsDayAndTimeRangeInTheLessonTimeZone() throws {
        let schedule = try #require(SchoolLessonHubRules.schedule(HubFixture.lesson()))
        #expect(schedule.contains("28") && schedule.hasSuffix("14:00 – 14:50"))
        #expect(schedule.first?.isUppercase == true)
    }

    // MARK: Permis

    @Test func permitCheckCommandMatchesTheStrictServerSchemaAndReceipt() throws {
        let id = UUID(), training = UUID()
        let body = try JSONEncoder().encode(SchoolRecordPermitCheck.seen(operationId: id, categoryCode: "B"))
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(object.keys) == ["operationId", "physicalSeen", "categoryCode", "decision"])
        #expect(object["physicalSeen"] as? Bool == true && object["decision"] as? String == "APPROVED" && object["categoryCode"] as? String == "B")
        let command = PendingSchoolCommand(id: id, scope: ConfigurationFixture.scope(), kind: .recordPermitCheck, resourceVersion: 0,
            createdAt: Date(), body: body, routeResourceID: training, expectedVersion: 3)
        #expect(command.hasValidTarget && command.kind.isReport && command.ifMatchVersion == 3)
        #expect(command.matches(SchoolOperationReceipt(operationId: id, commandType: "RECORD_PERMIT_CHECK", resourceType: "PermitCheck",
            resourceId: UUID(), committedAt: ConfigurationFixture.timestamp, resourceVersion: 1)))
        #expect(!command.matches(SchoolOperationReceipt(operationId: id, commandType: "COMPLETE_LESSON", resourceType: "Lesson",
            resourceId: UUID(), committedAt: ConfigurationFixture.timestamp, resourceVersion: 1)))
        let withoutRoute = PendingSchoolCommand(id: id, scope: ConfigurationFixture.scope(), kind: .recordPermitCheck, resourceVersion: 0,
            createdAt: Date(), body: body, expectedVersion: 3)
        #expect(!withoutRoute.hasValidTarget)
    }

    @Test func permitCheckSurvivesTheEncryptedOutbox() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DrivyPermit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let command = PendingSchoolCommand(id: id, scope: ConfigurationFixture.scope(), kind: .recordPermitCheck, resourceVersion: 0,
            createdAt: Date(), body: try JSONEncoder().encode(SchoolRecordPermitCheck.seen(operationId: id, categoryCode: "B")),
            routeResourceID: UUID(), expectedVersion: 2)
        let key = Data(repeating: 0x5C, count: 32)
        try EncryptedSchoolCommandOutbox(directory: directory, keyData: key).save(command)
        #expect(try EncryptedSchoolCommandOutbox(directory: directory, keyData: key).pending(for: command.scope) == command)
    }

    @Test func refusedPermitReviewIsNotALossOfAccess() {
        #expect(SchoolLessonReportClient.failure(403, "PERMIT_REVIEW_REQUIRED", kind: .recordPermitCheck) == .permitReviewRequired)
        #expect(SchoolLessonReportClient.failure(404, "NOT_FOUND", kind: .recordPermitCheck) == .permitReviewRequired)
        #expect(SchoolLessonReportClient.failure(403, "SETUP_ACCESS_REQUIRED", kind: .recordPermitCheck) == .forbidden)
        #expect(SchoolLessonReportClient.failure(403, "PERMIT_REVIEW_REQUIRED", kind: .completeLesson) == .forbidden)
        #expect(SchoolReportFailure.permitReviewRequired.permitsFreshCorrection)
        #expect(!SchoolTrainingAccess.isRevoked(SchoolReportFailure.permitReviewRequired))
    }

    @Test func seeingThePermitRecordsItThenReloadsWithoutLosingTypedText() async throws {
        let server = HubServer()
        let outbox = ConfigurationOutboxStub()
        let model = HubFixture.workspace(server: server, outbox: outbox)
        await model.load()
        #expect(model.lesson?.permitWarning == true && model.completionNeedsReason)
        #expect(model.mayRecordPermit && model.canMutate)
        model.administrativeNote = "Note en cours de saisie"
        #expect(await model.recordPermitSeen())
        let saved = try #require(outbox.saves.first)
        #expect(saved.kind == .recordPermitCheck && saved.routeResourceID == HubFixture.trainingID && saved.expectedVersion == 3)
        #expect(outbox.removals == [saved] && outbox.value == nil)
        let post = try #require(await server.requests().first(where: { $0.httpMethod == "POST" }))
        #expect(post.url?.path.hasSuffix("/trainings/\(HubFixture.trainingID.uuidString)/permit-checks") == true)
        #expect(post.value(forHTTPHeaderField: "If-Match") == "\"3\"")
        #expect(post.value(forHTTPHeaderField: "Idempotency-Key") == saved.id.uuidString)
        #expect(model.lesson?.permitWarning == false && !model.completionNeedsReason && model.permitRecorded && !model.mayRecordPermit)
        #expect(model.administrativeNote == "Note en cours de saisie")
        #expect(model.errorMessage == nil && model.confirmation == nil)
    }

    @Test func aRefusedPermitReviewKeepsTheLessonAndFallsBackToTheWrittenReason() async throws {
        let server = HubServer(permitStatus: 403)
        let outbox = ConfigurationOutboxStub()
        let model = HubFixture.workspace(server: server, outbox: outbox)
        await model.load()
        #expect(!(await model.recordPermitSeen()))
        #expect(model.lesson != nil && model.permitReviewDenied && !model.mayRecordPermit)
        #expect(model.completionNeedsReason && model.canMutate && outbox.value == nil)
        #expect(model.errorMessage == SchoolReportFailure.permitReviewRequired.localizedDescription)
    }

    @Test func withoutTheGrantThePermitButtonIsNotOffered() async {
        let model = HubFixture.workspace(server: HubServer(grants: []), outbox: ConfigurationOutboxStub(), grants: [])
        await model.load()
        #expect(model.lesson != nil && !model.mayRecordPermit)
    }

    @Test func changedServerPreparationDoesNotEraseOrSilentlyRebaseLocalEdits() async {
        let server = HubServer(), outbox = ConfigurationOutboxStub()
        let model = HubFixture.workspace(server: server, outbox: outbox)
        await model.load()
        model.administrativeNote = "Saisie privée non enregistrée"
        await server.setPreparation(note: "Modification depuis un autre appareil", version: 2)
        await model.load()
        #expect(model.administrativeNote == "Saisie privée non enregistrée")
        #expect(model.preparation?.version == 1 && model.needsReload && !model.canMutate)
        #expect(model.hasLocalEdits && model.retainedEditsText.contains("Saisie privée"))
        #expect(!(await model.savePreparation()) && outbox.saves.isEmpty)
        await model.load(discardingEdits: true)
        #expect(model.administrativeNote == "Modification depuis un autre appareil")
        #expect(model.preparation?.version == 2 && model.canMutate && !model.hasLocalEdits)
    }

    @Test func failedPreparationReadKeepsLocalEditsUntilRetry() async {
        let server = HubServer()
        let model = HubFixture.workspace(server: server, outbox: ConfigurationOutboxStub())
        await model.load()
        model.administrativeNote = "À conserver"
        await server.setPreparation(status: 503)
        await model.load()
        #expect(model.administrativeNote == "À conserver" && model.hasLocalEdits && !model.canMutate)
        await server.setPreparation()
        await model.load()
        #expect(model.administrativeNote == "À conserver" && model.canMutate && model.hasLocalEdits)
    }

    @Test func refreshRecognizesOwnSaveButNeverRebasesConcurrentEdits() {
        #expect(SchoolLessonRefreshPolicy.decide(previous: "avant", edited: "saisie", received: "saisie", discardingEdits: false) == .replace)
        #expect(SchoolLessonRefreshPolicy.decide(previous: "avant", edited: "saisie", received: "avant", discardingEdits: false) == .keepEdits)
        #expect(SchoolLessonRefreshPolicy.decide(previous: "avant", edited: "saisie", received: nil, discardingEdits: false) == .conflict)
        #expect(SchoolLessonRefreshPolicy.decide(previous: "avant", edited: "saisie", received: "autre", discardingEdits: false) == .conflict)
    }

    @Test func changedAccountCannotSendTheOldLessonsPendingMutation() async {
        let server = HubServer(), outbox = ConfigurationOutboxStub()
        let model = HubFixture.workspace(server: server, outbox: outbox)
        await model.load()
        model.administrativeNote = "Saisie du premier compte"
        await server.setPersonID(UUID())
        #expect(!(await model.savePreparation()))
        #expect(model.lesson == nil && !model.canMutate)
        #expect(outbox.value?.scope.personID == ConfigurationFixture.personID)
        #expect(await server.requests().allSatisfy { $0.httpMethod == "GET" })
    }
}

// MARK: Données de test

enum HubFixture {
    static let schoolID = ConfigurationFixture.schoolID
    static let lessonID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    static let trainingID = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!
    static let learnerID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!

    static func date(_ value: String) -> Date { SchoolLesson.date(value)! }

    static func lesson(status: String = "PLANNED", meetingPoint: String = "Gare de Lausanne", permitWarning: Bool = true) -> SchoolLesson {
        SchoolLesson(id: lessonID, schoolId: schoolID, version: 2, trainingId: trainingID, learnerId: learnerID,
            instructorMembershipId: ConfigurationFixture.membershipID, plannedStart: "2026-09-28T12:00:00Z", plannedEnd: "2026-09-28T12:50:00Z",
            timeZone: "Europe/Zurich", meetingPoint: meetingPoint, status: status, priceCentsSnapshot: 9_000, bufferMinutesSnapshot: 10,
            actualStart: nil, actualEnd: nil, permitWarning: permitWarning, publicationVersion: 0, currentPublishedRevisionId: nil,
            commercialRevisionVersion: 1)
    }

    static func school(gps: Bool) -> SchoolDetails {
        SchoolDetails(id: schoolID, schoolId: schoolID, version: 1, name: "École de test", timeZone: "Europe/Zurich", status: "ACTIVE",
            contactEmail: "ecole@example.invalid", contactPhone: nil, logoAssetId: nil,
            modules: .init(gpsEnabled: gps, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false),
            configurationVersion: 1)
    }

    static func capture(authorizedAt: String, stoppedAt: String?, state: SchoolCaptureSession.State, lesson: UUID = lessonID) -> SchoolCaptureSession {
        SchoolCaptureSession(id: UUID(), schoolId: schoolID, version: 1, lessonId: lesson, learnerId: learnerID,
            instructorMembershipId: ConfigurationFixture.membershipID, deviceId: UUID(), choiceId: UUID(), authorizedAt: authorizedAt,
            expiresAt: "2026-09-28T15:00:00Z", stoppedAt: stoppedAt, cutoffAt: nil, uploadDeadline: "2026-09-29T15:00:00Z",
            captureState: state, syncState: .localOnly, publicationState: .privateCapture, deviceAssessmentId: UUID())
    }

    @MainActor static func workspace(server: HubServer, outbox: ConfigurationOutboxStub, grants: [String] = ["permit_review"]) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: schoolID, schoolName: "École de test",
            roles: ["INSTRUCTOR"], grants: grants, accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: "https://api.example.invalid")!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: lessonID,
            client: client, outbox: outbox)
    }
}

@MainActor
final class HubToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-hub-token" }
}

/// Serveur synthétique : leçon planifiée sans contrôle de permis, puis contrôle AP30 et reçu AP72.
actor HubServer: SchoolHTTPTransport {
    private let permitStatus: Int
    private let grants: [String]
    private var permitRecorded = false
    private var trainingVersion = 3
    private var operation: UUID?
    private var recorded: [URLRequest] = []
    private var preparationNote: String?
    private var preparationVersion = 1
    private var preparationStatus = 200
    private var personID = ConfigurationFixture.personID
    private var startNowAvailable = false

    init(permitStatus: Int = 200, grants: [String] = ["permit_review"]) { self.permitStatus = permitStatus; self.grants = grants }
    func requests() -> [URLRequest] { recorded }
    func setPersonID(_ value: UUID) { personID = value }
    func enableStartNow() { startNowAvailable = true }
    func setPreparation(note: String? = nil, version: Int = 1, status: Int = 200) {
        preparationNote = note; preparationVersion = version; preparationStatus = status
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        recorded.append(request)
        let url = request.url!, parts = url.pathComponents.map { $0.lowercased() }
        let lesson = HubFixture.lessonID.uuidString.lowercased(), training = HubFixture.trainingID.uuidString.lowercased()
        func ok(_ data: [String: Any]) -> SchoolHTTPResponse {
            let envelope: [String: Any] = ["data": data, "requestId": UUID().uuidString.lowercased(), "serverTime": "2026-09-28T13:30:00Z"]
            return SchoolHTTPResponse(data: try! JSONSerialization.data(withJSONObject: envelope), status: 200, url: url, contentType: "application/json")
        }
        func problem(_ status: Int, _ code: String) -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\",\"title\":\"Refus\"}".utf8), status: status, url: url, contentType: "application/problem+json")
        }
        if parts.last == "me" {
            return ok(["personId": personID.uuidString, "version": 1, "displayName": "Moniteur de test", "locale": "fr",
                "memberships": [["membershipId": ConfigurationFixture.membershipID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                    "schoolName": "École de test", "roles": ["INSTRUCTOR"], "grants": grants, "accessEpoch": 1] as [String: Any]] as [Any]])
        }
        if request.httpMethod == "POST", parts.suffix(2) == ["lessons", "start-now"], startNowAvailable {
            return ok(try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson())) as? [String: Any] ?? [:])
        }
        if request.httpMethod == "POST", parts.suffix(3) == ["trainings", training, "permit-checks"] {
            if permitStatus != 200 { return problem(permitStatus, permitStatus == 403 ? "PERMIT_REVIEW_REQUIRED" : "NOT_FOUND") }
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            operation = UUID(uuidString: body?["operationId"] as? String ?? "")
            permitRecorded = true; trainingVersion += 1
            return ok(["id": UUID().uuidString, "schoolId": HubFixture.schoolID.uuidString, "version": 1, "trainingId": HubFixture.trainingID.uuidString,
                "documentId": NSNull(), "physicalSeen": true, "categoryCode": "B", "validUntil": NSNull(), "decision": "APPROVED",
                "reviewerMembershipId": ConfigurationFixture.membershipID.uuidString, "reviewedAt": "2026-09-28T13:30:00Z", "reason": NSNull(), "isExpired": false])
        }
        if parts.dropLast().last == "operations", let operation, parts.last == operation.uuidString.lowercased() {
            return ok(["operationId": operation.uuidString, "commandType": "RECORD_PERMIT_CHECK", "resourceType": "PermitCheck",
                "resourceId": UUID().uuidString, "committedAt": "2026-09-28T13:30:00Z", "resourceVersion": 1])
        }
        if parts.suffix(2) == ["lessons", lesson] {
            let value = HubFixture.lesson(permitWarning: !permitRecorded)
            return ok(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:])
        }
        if parts.suffix(2) == ["learners", HubFixture.learnerID.uuidString.lowercased()] {
            return ok(["id": HubFixture.learnerID.uuidString, "schoolId": HubFixture.schoolID.uuidString, "personId": UUID().uuidString,
                "version": 1, "displayName": "Élève de test", "contactEmail": NSNull(), "contactPhone": NSNull(), "archivedAt": NSNull()])
        }
        if parts.suffix(2) == ["trainings", training] {
            return ok(["id": HubFixture.trainingID.uuidString, "schoolId": HubFixture.schoolID.uuidString, "learnerId": HubFixture.learnerID.uuidString,
                "offeringId": UUID().uuidString, "version": trainingVersion, "categoryCode": "B", "status": "ACTIVE", "startedOn": NSNull(), "closedOn": NSNull()])
        }
        if parts.suffix(3) == ["lessons", lesson, "preparation"] {
            if preparationStatus != 200 { return problem(preparationStatus, "UNAVAILABLE") }
            return ok(["id": UUID(uuidString: "70000000-0000-4000-8000-000000000001")!.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "lessonId": HubFixture.lessonID.uuidString, "version": preparationVersion, "goals": [] as [Any], "administrativeCheckNote": preparationNote as Any? ?? NSNull(), "plannedWaypoints": [] as [Any]])
        }
        if parts.suffix(3) == ["lessons", lesson, "reports"] { return ok(["items": [] as [Any], "nextCursor": NSNull()]) }
        if parts.suffix(3) == ["lessons", lesson, "captures"] { return ok(["items": [] as [Any]]) }
        return problem(404, "NOT_FOUND")
    }
}
