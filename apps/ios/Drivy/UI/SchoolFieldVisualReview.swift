#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Parcours de contrôle isolé : données fictives, coffre temporaire chiffré, aucun réseau.
struct SchoolFieldVisualReview: View {
    let screen: String
    let context: SchoolVisualContext
    @State private var models: SchoolFieldVisualModels?
    @State private var route: FieldRoute?
    @State private var error: String?
    private enum FieldRoute: String, Identifiable { case choice, signal; var id: String { rawValue } }

    var body: some View {
        Group {
            if let models {
                if screen == "live" || screen == "live-waiting" {
                    SchoolCaptureLiveView(controller: screen == "live" ? models.live : models.waiting,
                        learnerName: context.learner.displayName)
                } else if screen == "observations" {
                    SchoolObservationView(model: models.observations, schoolWorkspace: context.workspace)
                } else if screen == "capture-preparation" {
                    SchoolCapturePreparationView(model: models.preparation, schoolWorkspace: context.workspace)
                } else {
                    NavigationStack {
                        VStack(spacing: DrivySpacing.l) {
                            Text("Leçon d’essai").font(.drivyScreenTitle)
                            if screen == "signal" {
                                Button("Signaler") { route = .signal }.buttonStyle(DrivyPrimaryButtonStyle())
                                if models.recorder.confirmed > 0 {
                                    Text("Observation enregistrée").accessibilityIdentifier("field-observation-saved")
                                }
                            } else {
                                Button("Choisir le GPS") { route = .choice }.buttonStyle(DrivyPrimaryButtonStyle())
                                if models.choice.choice?.status == .allowed {
                                    Text("Choix enregistré").accessibilityIdentifier("field-choice-saved")
                                }
                            }
                        }.drivyPageContent()
                    }
                    .sheet(item: $route) { value in
                        switch value {
                        case .choice: SchoolRecordingChoiceView(model: models.choice)
                        case .signal: SchoolLiveObservationSheet(recorder: models.recorder, observedAt: models.instant)
                        }
                    }
                }
            } else if let error { Text(error) }
            else { ProgressView("Préparation du contrôle…") }
        }
        .task {
            guard models == nil else { return }
            do {
                let loaded = try SchoolFieldVisualModels(context: context)
                models = loaded
                await loaded.recorder.loadCompetencies()
                if screen == "gps-choice" { route = .choice }
                if screen == "signal" { route = .signal }
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor private final class SchoolFieldVisualModels {
    let choice: SchoolRecordingChoiceWorkspace
    let recorder: SchoolLiveObservationRecorder
    let observations: SchoolObservationWorkspace
    let preparation: SchoolCapturePreparationWorkspace
    let live: SchoolCaptureSessionController
    let waiting: SchoolCaptureSessionController
    let instant = Date()

    init(context: SchoolVisualContext) throws {
        guard let person = context.workspace.person, let membership = context.workspace.membership else { throw SchoolAPIError.invalidResponse }
        let scope = context.agenda.scope(person: person, membership: membership)
        let transport = SchoolFieldVisualTransport(responses: try SchoolVisualData.responses())
        let baseURL = URL(string: "https://visual.drivy.invalid")!
        let token = SchoolVisualToken()
        let agenda = SchoolAgendaClient(baseURL: baseURL, tokenSource: token, transport: transport)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("field-visual-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Clé de fixture uniquement : ces données ne sortent jamais du simulateur DEBUG.
        let store = try SQLCipherSchoolCaptureStore(url: directory.appendingPathComponent("fixture.sqlite"), key: Data(repeating: 17, count: 32))
        choice = SchoolRecordingChoiceWorkspace(scope: scope, lessonID: SchoolVisualData.plannedLessonID,
            client: agenda.captureClient, reader: agenda.reader, agenda: agenda, onRefusalConfirmed: { _, _ in }, store: store)
        recorder = SchoolLiveObservationRecorder(scope: scope, lessonID: SchoolVisualData.plannedLessonID,
            client: agenda.observationClient, outbox: SchoolFieldVisualOutbox())
        live = SchoolCaptureSessionController.visualReviewRecording(lessonID: SchoolVisualData.plannedLessonID, recorder: recorder)
        waiting = SchoolCaptureSessionController.visualReviewRecording(lessonID: SchoolVisualData.plannedLessonID,
            recorder: recorder, waitingForPosition: true)
        observations = SchoolObservationWorkspace(scope: scope, lessonID: SchoolVisualData.plannedLessonID,
            client: agenda.observationClient, outbox: SchoolFieldVisualOutbox())
        preparation = SchoolCapturePreparationWorkspace(scope: scope, lessonID: SchoolVisualData.plannedLessonID,
            client: agenda.captureClient, reader: agenda.reader, agenda: agenda, store: store,
            onCaptureAuthorized: { _, _, _, _, _, _ in }, onRefusalConfirmed: { _, _ in })
    }
}

private actor SchoolFieldVisualTransport: SchoolHTTPTransport {
    let responses: [String: Data]
    private var recordedChoice: Data?
    init(responses: [String: Data]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "visual.drivy.invalid" else { throw SchoolAPIError.invalidResponse }
        func envelope(_ value: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString,
                "serverTime": "2026-09-29T10:00:00Z"])
        }
        if request.httpMethod == "POST", url.lastPathComponent == "recording-choice" {
            let body = try JSONDecoder().decode(SchoolRecordingChoiceBody.self, from: request.httpBody ?? Data())
            recordedChoice = try envelope(["id": body.operationId.uuidString, "schoolId": SchoolVisualData.schoolID.uuidString,
                "version": 2, "learnerId": SchoolVisualData.learnerID.uuidString, "lessonId": body.lessonId?.uuidString as Any? ?? NSNull(),
                "status": body.status.rawValue, "noticeVersionId": body.noticeVersionId.uuidString,
                "recordedBy": SchoolVisualData.membershipID.uuidString, "recordedAt": "2026-09-29T10:00:00Z", "source": body.source.rawValue])
        }
        if url.lastPathComponent == "recording-choice", let recordedChoice {
            return SchoolHTTPResponse(data: recordedChoice, status: 200, url: url, contentType: "application/json")
        }
        if request.httpMethod == "POST", url.lastPathComponent == "geo-observations" {
            var value = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
            value["id"] = value.removeValue(forKey: "operationId")
            value["schoolId"] = SchoolVisualData.schoolID.uuidString; value["version"] = 1
            value["lessonId"] = SchoolVisualData.plannedLessonID.uuidString
            value["trainingId"] = SchoolVisualData.trainingID.uuidString
            value["authorMembershipId"] = SchoolVisualData.membershipID.uuidString
            return SchoolHTTPResponse(data: try envelope(value), status: 201, url: url, contentType: "application/json")
        }
        guard (request.httpMethod ?? "GET") == "GET", let bytes = responses[url.path] else { throw SchoolAPIError.invalidResponse }
        return SchoolHTTPResponse(data: bytes, status: 200, url: url, contentType: "application/json")
    }
}

@MainActor private final class SchoolFieldVisualOutbox: SchoolCommandOutbox {
    private var value: PendingSchoolCommand?
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { value?.scope == scope ? value : nil }
    func save(_ command: PendingSchoolCommand) throws { value = command }
    func remove(_ command: PendingSchoolCommand) throws { if value?.id == command.id { value = nil } }
}
#endif
