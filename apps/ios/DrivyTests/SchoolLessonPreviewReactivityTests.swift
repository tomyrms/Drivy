import Foundation
import Testing
@testable import Drivy

/// #114 et #115 : l'aperçu du trajet d'une leçon terminée se télécharge page après page, sans retenir la fiche ni le
/// bilan, et un trajet synchronisé déjà lu n'est pas retéléchargé tant que l'école en garde la version. Aucune
/// position réelle : les points sont synthétiques.
@MainActor struct SchoolLessonPreviewReactivityTests {
    @Test func theLessonOpensAndStaysEditableWhileTheTripPreviewIsStillDownloading() async throws {
        let server = PreviewServer(), model = workspace(server)
        await server.hold()
        let loading = Task { await model.load() }
        try await HubFixture.wait { await server.isHolding() }
        try await HubFixture.wait { model.lesson != nil }
        // La fiche, le bilan et ses commandes ne dépendent pas de l'aperçu ; le trajet reste ouvrable depuis la liste.
        #expect(!model.isLoading && model.draft != nil && model.canMutate && model.acceptsInput)
        #expect(model.replayableCaptures.count == 1 && model.track.isEmpty && model.trackAnchors.isEmpty)
        await server.release()
        await loading.value
        await model.previewSettled()
        // L'aperçu arrive ensuite, sans nouvelle lecture de la fiche.
        #expect(!model.track.isEmpty && !model.trackAnchors.isEmpty)
        let reads = await server.replayReads()
        #expect(reads == 1)
    }

    @Test func aSyncedTripPreviewIsNotDownloadedAgainWhileTheSchoolKeepsItsVersion() async {
        let server = PreviewServer(), model = workspace(server)
        await model.load(); await model.previewSettled()
        #expect(!model.track.isEmpty)
        let first = await server.replayReads()
        #expect(first == 1)
        // Relecture de la fiche (après un enregistrement, au retour dans l'app) : même version, mêmes pages.
        await model.load(); await model.previewSettled()
        #expect(!model.track.isEmpty)
        let second = await server.replayReads()
        #expect(second == 1)
        // L'école change la version du trajet : il se relit.
        await server.setVersion(2)
        await model.load(); await model.previewSettled()
        #expect(!model.track.isEmpty)
        let third = await server.replayReads()
        #expect(third == 2)
    }

    @Test func aTripThatMayStillChangeIsAlwaysReadAgain() async {
        let server = PreviewServer(syncState: "PARTIAL"), model = workspace(server)
        await model.load(); await model.previewSettled()
        await model.load(); await model.previewSettled()
        #expect(!model.track.isEmpty)
        let reads = await server.replayReads()
        #expect(reads == 2)
    }

    @Test func aClosedSheetNeverReceivesALatePreview() async throws {
        let server = PreviewServer(), model = workspace(server)
        await server.hold()
        let loading = Task { await model.load() }
        try await HubFixture.wait { await server.isHolding() }
        try await HubFixture.wait { model.lesson != nil }
        model.close()
        await server.release()
        await loading.value
        await model.previewSettled()
        #expect(model.track.isEmpty && model.trackAnchors.isEmpty)
    }

    @Test func aNewerReadReplacesAPreviewStillInFlightAndPublishesItOnce() async throws {
        let server = PreviewServer(), model = workspace(server)
        await server.hold()
        let first = Task { await model.load() }
        try await HubFixture.wait { await server.isHolding() }
        try await HubFixture.wait { model.lesson != nil }
        let second = Task { await model.load() }
        try await HubFixture.wait { await server.waitingReads() == 2 }
        await server.release()
        await first.value; await second.value
        await model.previewSettled()
        #expect(!model.track.isEmpty && model.errorMessage == nil)
    }

    private func workspace(_ server: PreviewServer) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: ConfigurationOutboxStub())
    }
}

/// Leçon terminée avec un seul trajet synchronisé ; la lecture de ses pages peut être retenue puis relâchée.
private actor PreviewServer: SchoolHTTPTransport {
    nonisolated let captureID = UUID(uuidString: "70000000-0000-4000-8000-0000000000a1")!
    private let segmentID = UUID(uuidString: "70000000-0000-4000-8000-0000000000a2")!
    private let fallback = LessonFinishServer()
    private var version = 1
    private var syncState: String
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var reads = 0

    init(syncState: String = "SYNCED") { self.syncState = syncState }
    func hold() { held = true }
    func release() { held = false; let values = waiters; waiters = []; for item in values { item.resume() } }
    func isHolding() -> Bool { !waiters.isEmpty }
    func waitingReads() -> Int { waiters.count }
    func replayReads() -> Int { reads }
    func setVersion(_ value: Int) { version = value }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!, parts = url.pathComponents.map { $0.lowercased() }
        func ok(_ data: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
                "serverTime": "2026-09-28T13:30:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        if parts.suffix(3) == ["lessons", HubFixture.lessonID.uuidString.lowercased(), "captures"] {
            let capture = SchoolCaptureSession(id: captureID, schoolId: HubFixture.schoolID, version: version,
                lessonId: HubFixture.lessonID, learnerId: HubFixture.learnerID, instructorMembershipId: ConfigurationFixture.membershipID,
                deviceId: nil, choiceId: UUID(), authorizedAt: "2026-09-28T12:00:00Z", expiresAt: "2026-09-28T15:00:00Z",
                stoppedAt: "2026-09-28T12:50:00Z", cutoffAt: nil, uploadDeadline: "2026-09-29T15:00:00Z",
                captureState: .stopped, syncState: .synced, publicationState: .privateCapture, deviceAssessmentId: nil)
            var item = try JSONSerialization.jsonObject(with: JSONEncoder().encode(capture)) as! [String: Any]
            item["syncState"] = syncState
            return try ok(["items": [item]])
        }
        if parts.last == "replay", parts.dropLast().last == captureID.uuidString.lowercased() {
            reads += 1
            if held { await withCheckedContinuation { waiters.append($0) } }
            let start = SchoolLesson.date("2026-09-28T12:00:00Z")!
            let points = (0..<6).map { index in
                SchoolCapturePoint(sequence: index, elapsedMs: index * 1_000,
                    capturedAt: SchoolCaptureLocationTime.timestamp(start.addingTimeInterval(Double(index))),
                    latitude: 46.5, longitude: 6.6 + Double(index) / 10_000, accuracyMeters: 3)
            }
            let page = SchoolPrivateReplayPage(captureId: captureID, quality: "SYNCED", publicationState: .privateCapture,
                segments: [.init(segmentId: segmentID, segmentIndex: 0, points: points, hasGapBefore: false,
                    qualityLabel: "AVAILABLE", continuesFromPreviousPage: false, continuesOnNextPage: false)],
                observations: [], nextCursor: nil, generatedAt: "2026-09-28T13:30:00Z", reportRevisionId: nil, geometrySnapshotId: nil)
            return try ok(try JSONSerialization.jsonObject(with: JSONEncoder().encode(page)))
        }
        return try await fallback.send(request)
    }
}
