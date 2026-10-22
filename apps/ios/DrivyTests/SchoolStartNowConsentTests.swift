import Foundation
import Testing
@testable import Drivy

/// Accord GPS du démarrage immédiat (#95) : ce que le récapitulatif montre selon ce qui est réellement vérifié.
/// Transport synthétique, journal chiffré temporaire, aucune position.
@MainActor struct SchoolStartNowConsentTests {
    private typealias Display = SchoolStartNowGPS.Display

    @Test func anUnverifiedStateIsNeverAKnownChoiceNorAFirstQuestion() {
        // (notice lue, lecture en cours, erreur, droit retiré, demande en attente)
        let cases: [(Bool, Bool, Bool, Bool, Bool)] = [
            (false, true, false, false, false), (false, false, false, false, false), (false, false, true, false, false),
            (true, false, false, true, false), (true, false, false, false, true),
        ]
        for (notice, loading, error, revoked, pending) in cases {
            let display = Display.resolve(hasNotice: notice, isLoading: loading, hasError: error, accessRevoked: revoked,
                hasPendingOrOldScope: pending, answer: .allowed, isChanging: false)
            #expect(display != .question)
            if case .known = display { Issue.record("Un état non vérifié ne vaut pas choix connu") }
        }
    }

    @Test func theDisplayFollowsTheVerifiedChoice() {
        func resolve(_ answer: SchoolRecordingChoice.Status?, changing: Bool = false) -> Display {
            .resolve(hasNotice: true, isLoading: false, hasError: false, accessRevoked: false,
                hasPendingOrOldScope: false, answer: answer, isChanging: changing)
        }
        #expect(resolve(.allowed) == .known(.allowed))
        #expect(resolve(.refused) == .known(.refused))
        #expect(resolve(nil) == .question)
        #expect(resolve(.allowed, changing: true) == .question)
        #expect(Display.resolve(hasNotice: false, isLoading: true, hasError: true, accessRevoked: false,
            hasPendingOrOldScope: false, answer: nil, isChanging: false) == .reading)
        #expect(Display.resolve(hasNotice: false, isLoading: false, hasError: true, accessRevoked: false,
            hasPendingOrOldScope: false, answer: nil, isChanging: false) == .unavailable)
    }

    @Test func aGeneralAllowedChoiceIsReusedWithoutQuestionNorWrite() async throws {
        let fixture = try await ConsentFixture.make(.recorded(.allowed))
        await fixture.gps.load()
        #expect(fixture.gps.display == .known(.allowed))
        #expect(fixture.gps.recorded == .allowed && fixture.gps.selection == nil)
        #expect(fixture.gps.wantsTrip && !fixture.gps.isReading)
        #expect(await fixture.server.writes() == 0)
        // Rien à enregistrer au départ : le choix connu est déjà celui de l’école.
        #expect(await fixture.gps.commit())
        #expect(await fixture.server.writes() == 0)
    }

    @Test func aRememberedRefusalIsKeptAndStartsWithoutGPS() async throws {
        let fixture = try await ConsentFixture.make(.recorded(.refused))
        await fixture.gps.load()
        #expect(fixture.gps.display == .known(.refused))
        #expect(!fixture.gps.wantsTrip)
        #expect(await fixture.gps.commit())
        #expect(await fixture.server.writes() == 0)
    }

    @Test func noChoiceAtAllAsksTheQuestionWithoutPreselection() async throws {
        let fixture = try await ConsentFixture.make(.absent)
        await fixture.gps.load()
        #expect(fixture.gps.display == .question)
        #expect(fixture.gps.answer == nil && !fixture.gps.wantsTrip)
        #expect(!(await fixture.gps.commit()))
        #expect(await fixture.server.writes() == 0)
    }

    @Test func anUnknownOrOutdatedChoiceAsksAgainAndNeverCountsAsAccepted() async throws {
        for mode in [ConsentFixture.Mode.recorded(.unknown), .staleNotice(.allowed)] {
            let fixture = try await ConsentFixture.make(mode)
            await fixture.gps.load()
            #expect(fixture.gps.display == .question)
            #expect(fixture.gps.recorded == nil && !fixture.gps.wantsTrip)
        }
    }

    @Test func aSlowReadIsNotAnAbsentChoiceAndBlocksTheDeparture() async throws {
        let fixture = try await ConsentFixture.make(.recorded(.allowed))
        await fixture.server.holdChoiceReads()
        let reading = Task { await fixture.gps.load() }
        try await HubFixture.wait { await fixture.server.isWaitingForChoice() }
        #expect(fixture.gps.display == .reading)
        #expect(fixture.gps.isReading && !fixture.gps.wantsTrip)
        await fixture.server.releaseChoiceReads()
        await reading.value
        #expect(fixture.gps.display == .known(.allowed) && !fixture.gps.isReading)
    }

    @Test func aReadFailureIsNeitherAFirstQuestionNorAConsent() async throws {
        let fixture = try await ConsentFixture.make(.failing)
        await fixture.gps.load()
        #expect(fixture.gps.display == .unavailable)
        #expect(!fixture.gps.wantsTrip && fixture.gps.answer == nil)
        #expect(await fixture.server.writes() == 0)
    }

    @Test func aFailedRereadDropsAChoiceReadBeforeIt() async throws {
        let fixture = try await ConsentFixture.make(.recorded(.allowed))
        await fixture.gps.load()
        try #require(fixture.gps.display == .known(.allowed))
        await fixture.server.setFailing(true)
        await fixture.gps.refresh()
        #expect(fixture.gps.display == .unavailable)
        #expect(!fixture.gps.isReading)
        #expect(!fixture.gps.consentIsClear)
        await fixture.server.setFailing(false)
        await fixture.gps.refresh()
        #expect(fixture.gps.display == .known(.allowed))
    }

    @Test func aChoiceChangedElsewhereIsReadAgainOnReturn() async throws {
        let fixture = try await ConsentFixture.make(.recorded(.allowed))
        await fixture.gps.load()
        try #require(fixture.gps.display == .known(.allowed))
        await fixture.server.setMode(.recorded(.refused))
        await fixture.gps.refresh()
        #expect(fixture.gps.display == .known(.refused) && !fixture.gps.wantsTrip)
    }

    @Test func changingTheChoiceReopensTheQuestionWithoutWritingAnything() async throws {
        let fixture = try await ConsentFixture.make(.recorded(.allowed))
        await fixture.gps.load()
        fixture.gps.beginChanging()
        #expect(fixture.gps.display == .question && fixture.gps.isChanging)
        #expect(fixture.gps.recorded == .allowed && fixture.gps.selection == nil)
        #expect(await fixture.server.writes() == 0)
        // Choisir à nouveau la même réponse referme la question sans rien à enregistrer.
        fixture.gps.select(.allowed)
        #expect(fixture.gps.display == .known(.allowed) && fixture.gps.selection == nil)
        fixture.gps.beginChanging()
        fixture.gps.select(.refused)
        #expect(fixture.gps.selection == .refused && fixture.gps.answer == .refused && !fixture.gps.wantsTrip)
        #expect(await fixture.server.writes() == 0)
    }

    @Test func aChangedChoiceIsWrittenOnlyAtDeparture() async throws {
        let fixture = try await ConsentFixture.make(.recorded(.allowed))
        await fixture.gps.load()
        fixture.gps.beginChanging()
        fixture.gps.select(.refused)
        #expect(await fixture.server.writes() == 0)
        #expect(await fixture.gps.commit())
        #expect(await fixture.server.writes() == 1)
        #expect(fixture.gps.recorded == .refused)
    }

    @Test func aProtectedRefusalCannotBeReplacedByAVerbalAgreement() async throws {
        let fixture = try await ConsentFixture.make(.protectedRefusal)
        await fixture.gps.load()
        #expect(fixture.gps.display == .known(.refused))
        #expect(fixture.gps.consent.verbalAgreementIsProtected)
        #expect(fixture.gps.consent.review(.allowed) == nil)
    }

    @Test func aDeviceThatCannotLocateIsStillTold() async throws {
        let denied = try await ConsentFixture.make(.recorded(.allowed), permission: .denied)
        await denied.gps.load()
        #expect(denied.gps.display == .known(.allowed))
        #expect(denied.gps.device == .denied && !denied.gps.wantsTrip)
        let approximate = try await ConsentFixture.make(.recorded(.allowed), precise: false)
        await approximate.gps.load()
        #expect(approximate.gps.device == .approximate && !approximate.gps.wantsTrip)
    }

    @Test func aLateReadOfAPreviousLearnerIsNeverAppliedToTheNextOne() async throws {
        let first = try await ConsentFixture.make(.recorded(.allowed))
        await first.server.holdChoiceReads()
        let reading = Task { await first.gps.load() }
        try await HubFixture.wait { await first.server.isWaitingForChoice() }
        // Changement d’élève : le modèle précédent est fermé avant que sa réponse n’arrive.
        first.gps.close()
        await first.server.releaseChoiceReads()
        await reading.value
        #expect(first.gps.consent.choice == nil && first.gps.consent.notice == nil)
        #expect(first.gps.display != .known(.allowed) && !first.gps.wantsTrip)
    }
}

/// Un élève, son école synthétique et le modèle d’accord GPS du récapitulatif.
@MainActor struct ConsentFixture {
    enum Mode: Equatable, Sendable {
        case absent, failing, protectedRefusal
        case recorded(SchoolRecordingChoice.Status)
        case staleNotice(SchoolRecordingChoice.Status)
    }

    let server: ConsentServer
    let gps: SchoolStartNowGPS

    static func make(_ mode: Mode, permission: SchoolCaptureLocationPermission = .foreground,
                     precise: Bool = true) async throws -> ConsentFixture {
        let scope = ConfigurationFixture.scope(), learner = UUID()
        let server = ConsentServer(scope: scope, learnerID: learner, mode: mode)
        let agenda = SchoolAgendaClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let store = try SQLCipherSchoolCaptureStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("consent-\(UUID()).sqlite"),
            key: Data(repeating: 0x5A, count: 32), protectFiles: false, installationID: UUID())
        let consent = SchoolRecordingChoiceWorkspace(scope: scope, lessonID: nil, learnerID: learner, client: agenda.captureClient,
            reader: agenda.reader, agenda: agenda, onRefusalConfirmed: { _, _ in }, store: store)
        let source = ConsentLocation(permission: permission, precise: precise)
        let gps = SchoolStartNowGPS(learnerID: learner, consent: consent, source: source, scope: scope)
        return ConsentFixture(server: server, gps: gps)
    }
}

@MainActor private final class ConsentLocation: SchoolCaptureLocationProviding {
    var onEvent: (@MainActor (SchoolCaptureLocationEvent) -> Void)?
    let permission: SchoolCaptureLocationPermission
    let preciseLocation: Bool
    var isRunning: Bool { false }
    init(permission: SchoolCaptureLocationPermission, precise: Bool) { self.permission = permission; preciseLocation = precise }
    func requestPermission() {}
    func requestDiagnosticSample() throws { throw SchoolCaptureLocationFailure.permissionRequired }
    func diagnosticSnapshot() throws -> SchoolCaptureDeviceSnapshot { throw SchoolCaptureLocationFailure.permissionRequired }
    func diagnosticBody(operationID: UUID, networkAvailable: Bool) throws -> SchoolDeviceAssessmentBody {
        throw SchoolCaptureLocationFailure.permissionRequired
    }
    func updateScope(_ scope: SchoolCommandScope?) {}
    func prepareSegment(authorization: SchoolCaptureAuthorization, lease: SchoolCaptureLease, scope: SchoolCommandScope,
                        clockReference: SchoolCaptureClockReference, policy: SchoolCaptureLocationPolicy) throws -> SchoolCaptureLocationSegment {
        throw SchoolCaptureLocationFailure.permissionRequired
    }
    func start(segment: SchoolCaptureLocationSegment, handle: SchoolCaptureSegmentHandle) throws {
        throw SchoolCaptureLocationFailure.permissionRequired
    }
    @discardableResult func stop() -> SchoolCaptureLocationStop? { nil }
}

actor ConsentServer: SchoolHTTPTransport {
    private let scope: SchoolCommandScope
    private let learnerID: UUID
    private let noticeID = UUID(), staleNoticeID = UUID()
    private var mode: ConsentFixture.Mode
    private var failing = false
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var writeCount = 0
    private let stamp = "2026-09-29T10:00:00Z"

    init(scope: SchoolCommandScope, learnerID: UUID, mode: ConsentFixture.Mode) {
        self.scope = scope; self.learnerID = learnerID; self.mode = mode
        failing = mode == .failing
    }

    func writes() -> Int { writeCount }
    func setMode(_ value: ConsentFixture.Mode) { mode = value }
    func setFailing(_ value: Bool) { failing = value }
    func holdChoiceReads() { held = true }
    func isWaitingForChoice() -> Bool { !waiters.isEmpty }
    func releaseChoiceReads() { held = false; let values = waiters; waiters = []; for item in values { item.resume() } }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func json(_ value: Any, status: Int = 200) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString,
                "serverTime": stamp]), status: status, url: url, contentType: "application/json")
        }
        func problem(_ code: String, status: Int) -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\"}".utf8), status: status, url: url, contentType: "application/problem+json")
        }
        func ok<T: Encodable>(_ value: T) throws -> SchoolHTTPResponse { try json(JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) }
        let leaf = url.lastPathComponent
        if request.httpMethod == "POST" { writeCount += 1 }
        if leaf == "me" {
            return try ok(SchoolPerson(personId: scope.personID, version: 1, displayName: "Moniteur synthétique", locale: "fr",
                memberships: [.init(membershipId: scope.membershipID, schoolId: scope.schoolID, schoolName: "École synthétique",
                    roles: ["INSTRUCTOR"], grants: [], accessEpoch: scope.accessEpoch)]))
        }
        if leaf.lowercased() == learnerID.uuidString.lowercased() {
            return try json(["id": learnerID.uuidString, "schoolId": scope.schoolID.uuidString, "personId": UUID().uuidString,
                "version": 1, "displayName": "Élève synthétique", "contactEmail": NSNull(), "contactPhone": NSNull(),
                "archivedAt": NSNull(), "profileReadiness": NSNull(), "profilePhotoDocumentId": NSNull()])
        }
        if leaf == "recording-notice" {
            if failing { return problem("UNAVAILABLE", status: 503) }
            return try json(["noticeVersionId": noticeID.uuidString, "noticeText": "Information GPS synthétique",
                "retentionText": "Conservation de test", "contactEmail": "ecole@example.invalid", "approvedAt": stamp])
        }
        if leaf == "recording-choice" {
            if held { await withCheckedContinuation { waiters.append($0) } }
            if failing { return problem("UNAVAILABLE", status: 503) }
            if request.httpMethod == "POST" {
                let body = try JSONDecoder().decode(SchoolRecordingChoiceBody.self, from: request.httpBody ?? Data())
                mode = .recorded(body.status)
                return try json(choice(status: body.status, notice: body.noticeVersionId, source: body.source, id: body.operationId))
            }
            switch mode {
            case .absent, .failing: return problem("RECORDING_CHOICE_NOT_SET", status: 404)
            case .recorded(let status): return try json(choice(status: status, notice: noticeID, source: .verbal))
            case .staleNotice(let status): return try json(choice(status: status, notice: staleNoticeID, source: .verbal))
            case .protectedRefusal: return try json(choice(status: .refused, notice: noticeID, source: .own))
            }
        }
        return problem("NOT_FOUND", status: 404)
    }

    /// Identifiant stable entre deux lectures : `confirm` refuse d'écrire si le choix lu a changé entre-temps.
    private let readChoiceID = UUID()

    private func choice(status: SchoolRecordingChoice.Status, notice: UUID, source: SchoolRecordingChoice.Source,
                        id: UUID? = nil) -> [String: Any] {
        ["id": (id ?? readChoiceID).uuidString, "schoolId": scope.schoolID.uuidString, "version": 1, "learnerId": learnerID.uuidString,
         "lessonId": NSNull(), "status": status.rawValue, "noticeVersionId": notice.uuidString,
         "recordedBy": scope.membershipID.uuidString, "recordedAt": stamp, "source": source.rawValue]
    }
}
