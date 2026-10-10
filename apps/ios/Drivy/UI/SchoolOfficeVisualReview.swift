#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Écrans natifs avec transport synthétique isolé. Aucune requête ni commande réelle.
struct SchoolOfficeVisualReview: View {
    let screen: String
    let context: SchoolVisualContext
    @State private var models: SchoolOfficeVisualModels?
    @State private var report: OfficeReportRoute?
    @State private var error: String?
    @State private var reportClosed = false
    private struct OfficeReportRoute: Identifiable { let id: UUID }

    var body: some View {
        Group {
            if let models {
                switch screen {
                case "planning": SchoolPlanningView(model: models.planning)
                case "start-now": SchoolStartNowView(launch: models.startNowLaunch)
                case "planning-settings":
                    NavigationStack {
                        SchoolPlanningSettingsView(scope: models.planning.scope, client: models.agenda.planningClient,
                            outbox: models.outbox)
                    }
                case "invitation-create": InvitationCreationView(model: models.invitations)
                case "invitations", "invitation-detail": SchoolInvitationsView(model: models.invitations)
                case "lesson-tariff":
                    NavigationStack {
                        SchoolLessonReportView(client: models.agenda.reportClient, schoolWorkspace: context.workspace,
                            lessonID: SchoolVisualData.lessonID, learnerName: context.learner.displayName, outbox: models.outbox)
                    }
                default:
                    NavigationStack {
                        VStack(spacing: DrivySpacing.l) {
                            if reportClosed {
                                Text("Leçon enregistrée").font(.drivyTitle).accessibilityIdentifier("field-lesson-closed")
                            } else {
                                Button("Ouvrir la leçon") { report = OfficeReportRoute(id: SchoolVisualData.plannedLessonID) }.buttonStyle(DrivyPrimaryButtonStyle())
                            }
                        }.drivyPageContent()
                    }
                    .sheet(item: $report, onDismiss: { reportClosed = true }) { route in
                        NavigationStack {
                            SchoolLessonReportView(client: models.agenda.reportClient, schoolWorkspace: context.workspace,
                                lessonID: route.id, learnerName: context.learner.displayName,
                                opensCompletion: screen == "lesson-permit", outbox: models.outbox)
                        }
                    }
                }
            } else if let error { ContentUnavailableView("Rendu indisponible", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView("Préparation du contrôle…") }
        }
        .task {
            guard models == nil else { return }
            do {
                let loaded = try SchoolOfficeVisualModels(context: context, permitWarning: screen == "lesson-permit")
                await loaded.prepare(screen: screen)
                models = loaded
                if screen == "lesson-finish" || screen == "lesson-permit" { report = OfficeReportRoute(id: SchoolVisualData.plannedLessonID) }
                if screen == "lesson-modal" { report = OfficeReportRoute(id: SchoolVisualData.lessonID) }
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor private final class SchoolOfficeVisualModels {
    let agenda: SchoolAgendaClient
    let planning: SchoolPlanningWorkspace
    let startNow: SchoolStartNowWorkspace
    let startNowLaunch: SchoolStartNowLaunch
    let invitations: SchoolInvitationWorkspace
    let outbox: SchoolOfficeVisualOutbox

    init(context: SchoolVisualContext, permitWarning: Bool = false) throws {
        guard let person = context.workspace.person, let membership = context.workspace.membership else { throw SchoolAPIError.invalidResponse }
        let scope = context.agenda.scope(person: person, membership: membership)
        let baseURL = URL(string: "https://visual.drivy.invalid")!, token = SchoolVisualToken()
        let transport = SchoolOfficeVisualTransport(responses: try SchoolOfficeVisualData.responses(permitWarning: permitWarning),
            allowsWrites: !permitWarning)
        let outbox = SchoolOfficeVisualOutbox(allowsWrites: !permitWarning)
        self.outbox = outbox
        let agenda = SchoolAgendaClient(baseURL: baseURL, tokenSource: token, transport: transport)
        self.agenda = agenda
        planning = SchoolPlanningWorkspace(scope: scope, client: agenda.planningClient, date: Date().addingTimeInterval(86_400), outbox: outbox)
        let startForm = SchoolStartNowWorkspace(scope: scope, client: agenda.planningClient,
            learnerID: SchoolVisualData.learnerID, outbox: outbox)
        startNow = startForm
        // Sans contrôleur de trajet : la capture montre le récapitulatif, sans accord GPS ni rideau.
        startNowLaunch = SchoolStartNowLaunch(form: startForm, agenda: agenda, workspace: context.workspace, controller: nil)
        invitations = SchoolInvitationWorkspace(scope: scope, roles: membership.roles,
            api: SchoolInvitationClient(baseURL: baseURL, tokenSource: token, transport: transport), outbox: outbox)
    }

    func prepare(screen: String) async {
        switch screen {
        case "planning":
            await planning.load()
            await planning.selectLearner(SchoolVisualData.learnerID)
            await planning.selectTraining(SchoolVisualData.trainingID)
            planning.instructorID = SchoolVisualData.membershipID
            planning.productID = SchoolOfficeVisualData.productID
            planning.meetingPoint = "Gare de Cernier"
            await planning.loadAvailability()
        case "invitations", "invitation-create", "invitation-detail":
            await invitations.load()
            if screen == "invitation-detail" { invitations.selectedID = invitations.invitations.first?.id }
        default: break
        }
    }
}

@MainActor private enum SchoolOfficeVisualData {
    static let productID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    static let termsID = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
    static func responses(permitWarning: Bool = false) throws -> [String: Data] {
        var responses = try SchoolVisualData.responses()
        let school = SchoolVisualData.schoolID.uuidString, member = SchoolVisualData.membershipID.uuidString
        let root = "/v1/schools/\(school)"
        func envelope(_ value: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString, "serverTime": "2026-09-29T10:00:00Z"])
        }
        func page(_ items: [[String: Any]]) -> [String: Any] { ["items": items, "nextCursor": NSNull()] }
        responses["\(root)/service-products"] = try envelope(page([["id": productID.uuidString, "schoolId": school, "version": 1,
            "productKey": "lesson-example", "label": "Leçon de conduite", "type": "INDIVIDUAL_LESSON", "categoryCode": "B",
            "durationMinutes": 50, "siteId": NSNull(), "unitLabel": "leçon", "unitPriceCents": 9500,
            "validFrom": "2026-01-01", "validUntil": NSNull(), "termsVersionId": termsID.uuidString, "enabled": true]]))
        responses["\(root)/commercial-terms"] = try envelope(page([["id": termsID.uuidString, "schoolId": school, "version": 1,
            "label": "Conditions de la leçon", "termsText": "Conditions fictives du contrôle de rendu.", "validFrom": "2026-01-01",
            "validUntil": NSNull(), "approved": true]]))
        responses["\(root)/trainings/\(SchoolVisualData.trainingID.uuidString)/assignments"] = try envelope(page([
            ["id": UUID().uuidString, "schoolId": school, "version": 1, "trainingId": SchoolVisualData.trainingID.uuidString,
                "instructorMembershipId": member, "validFrom": "2026-01-01T00:00:00Z", "validUntil": NSNull()]]))
        responses["\(root)/availability-rules"] = try envelope(page([["id": UUID().uuidString, "schoolId": school, "version": 1,
            "instructorMembershipId": member, "weekdays": [1, 2, 3, 4, 5, 6, 7], "localStart": "07:00", "localEnd": "20:00",
            "validFrom": "2026-01-01", "validUntil": NSNull()]]))
        responses["\(root)/closures"] = try envelope(page([]))
        // Réponse explicitement synthétique : le rendu ne qualifie pas le contrôle de réservation serveur.
        responses["\(root)/lessons/availability"] = try envelope(["available": true, "reasonCode": NSNull()])
        let invitations: [[String: Any]] = ["PENDING", "ACCEPTED", "EXPIRED"].map { status in
            ["id": UUID().uuidString, "schoolId": school, "version": 1, "maskedEmail": NSNull(), "roles": ["LEARNER"],
                "status": status, "expiresAt": "2026-10-06T10:00:00Z", "delivery": "CODE", "trainingCategoryCode": "B",
                "training": ["offeringId": SchoolVisualData.offeringID.uuidString, "instructorMembershipId": member]]
        }
        responses["\(root)/invitations"] = try envelope(page(invitations))
        // Le bilan de la leçon d’essai est réellement vide pour le test de sauvegarde.
        let planned = "\(root)/lessons/\(SchoolVisualData.plannedLessonID.uuidString)"
        if permitWarning {
            guard let bytes = responses[planned],
                  let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  var lesson = value["data"] as? [String: Any] else { throw SchoolAPIError.invalidResponse }
            lesson["permitWarning"] = true
            // Ce scénario ouvre la fin d’une leçon déjà commencée explicitement.
            lesson["actualStart"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3000))
            responses[planned] = try envelope(lesson)
        }
        if let bytes = responses["\(root)/lessons/\(SchoolVisualData.lessonID.uuidString)/report-drafts"],
           let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let data = value["data"] as? [String: Any], var draft = (data["items"] as? [[String: Any]])?.first {
            draft["lessonId"] = SchoolVisualData.plannedLessonID.uuidString
            draft["workedOn"] = ""; draft["observationText"] = ""; draft["nextStep"] = ""; draft["observations"] = [] as [Any]
            responses["\(planned)/report-drafts"] = try envelope(page([draft]))
        }
        responses["\(planned)/sharing"] = try envelope(["lessonId": SchoolVisualData.plannedLessonID.uuidString,
            "schoolId": school, "version": 1, "reportPrivate": false, "captureHidden": false, "privateObservationIds": [] as [Any]])
        return responses
    }
}

private actor SchoolOfficeVisualTransport: SchoolHTTPTransport {
    private var responses: [String: Data]
    private let allowsWrites: Bool
    init(responses: [String: Data], allowsWrites: Bool = true) {
        self.responses = responses
        self.allowsWrites = allowsWrites
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "visual.drivy.invalid" else { throw SchoolAPIError.invalidResponse }
        guard allowsWrites || (request.httpMethod ?? "GET") == "GET" else { throw SchoolAPIError.invalidResponse }
        func envelope(_ value: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString, "serverTime": "2026-09-29T10:00:00Z"])
        }
        if request.httpMethod == "POST", ["start", "complete"].contains(url.lastPathComponent) {
            let lessonPath = url.deletingLastPathComponent().path
            guard let bytes = responses[lessonPath], let envelopeObject = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  var lesson = envelopeObject["data"] as? [String: Any],
                  let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] else { throw SchoolAPIError.invalidResponse }
            let version = (lesson["version"] as? Int ?? 1) + 1
            lesson["version"] = version
            if url.lastPathComponent == "start" {
                lesson["actualStart"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
            } else {
                lesson["status"] = "COMPLETED"
                lesson["actualEnd"] = body["actualEnd"]
            }
            responses[lessonPath] = try envelope(lesson)
            try receipt(body: body, url: url, command: url.lastPathComponent == "start" ? "START_LESSON" : "COMPLETE_LESSON",
                resource: "Lesson", id: lesson["id"] as! String, version: version)
            return SchoolHTTPResponse(data: try envelope([:]), status: 200, url: url, contentType: "application/json")
        }
        if request.httpMethod == "PUT", url.path.contains("/report-drafts/"),
           let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] {
            try receipt(body: body, url: url, command: "SAVE_REPORT_DRAFT", resource: "ReportDraft", id: url.lastPathComponent)
            return SchoolHTTPResponse(data: try envelope([:]), status: 200, url: url, contentType: "application/json")
        }
        guard (request.httpMethod ?? "GET") == "GET", let bytes = responses[url.path] else {
            return SchoolHTTPResponse(data: Data("{\"code\":\"NOT_FOUND\",\"title\":\"Donnée fictive absente\"}".utf8), status: 404,
                url: url, contentType: "application/problem+json")
        }
        return SchoolHTTPResponse(data: bytes, status: 200, url: url, contentType: "application/json")
    }

    private func receipt(body: [String: Any], url: URL, command: String, resource: String, id: String, version: Int = 2) throws {
        guard let operation = body["operationId"] as? String else { throw SchoolAPIError.invalidResponse }
        let schoolRoot = url.pathComponents.prefix(4).joined(separator: "/").replacingOccurrences(of: "//", with: "/")
        let data: [String: Any] = ["operationId": operation, "commandType": command, "resourceType": resource,
            "resourceId": id, "resourceVersion": version, "committedAt": "2026-09-29T10:00:00Z"]
        responses["\(schoolRoot)/operations/\(operation)"] = try JSONSerialization.data(withJSONObject: ["data": data,
            "requestId": UUID().uuidString, "serverTime": "2026-09-29T10:00:00Z"])
    }
}

@MainActor private final class SchoolOfficeVisualOutbox: SchoolCommandOutbox {
    private var value: PendingSchoolCommand?
    private let allowsWrites: Bool
    init(allowsWrites: Bool = true) { self.allowsWrites = allowsWrites }
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { value?.scope == scope ? value : nil }
    func save(_ command: PendingSchoolCommand) throws {
        guard allowsWrites else { throw SchoolConfigurationFailure.storage }
        value = command
    }
    func remove(_ command: PendingSchoolCommand) throws { if value?.id == command.id { value = nil } }
}
#endif
