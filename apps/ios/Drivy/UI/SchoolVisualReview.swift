#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Actual school screens using an isolated, read-only in-memory transport.
/// No production credentials, persistent school store or network transport is created.
struct SchoolVisualReview: View {
    /// Shell screens routed here directly by DrivyApp, with the real tab bar.
    static let shellScreens: Set<String> = ["home-tabs", "agenda", "learners", "learner", "school"]

    let screen: String
    @State private var context: SchoolVisualContext?
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var systemTextSize

    var body: some View {
        Group {
            if let context {
                switch screen {
                case "catalog":
                    SchoolCatalogView(model: context.catalog)
                case "dossier":
                    SchoolTrainingView(client: context.client, workspace: context.workspace,
                        learner: context.learner, trainingID: SchoolVisualData.trainingID)
                case "home-tabs":
                    SchoolVisualShell(context: context, tab: .session)
                case "agenda":
                    SchoolVisualShell(context: context, tab: .agenda)
                case "learners":
                    SchoolVisualShell(context: context, tab: .learners)
                case "learner":
                    SchoolVisualShell(context: context, tab: .learners, learnerID: SchoolVisualData.learnerID)
                case "school":
                    SchoolVisualShell(context: context, tab: .school)
                default:
                    NavigationStack {
                        SchoolPublishedRevisionView(client: context.client, schoolID: SchoolVisualData.schoolID,
                            trainingID: SchoolVisualData.trainingID, lessonID: SchoolVisualData.lessonID,
                            revisionID: SchoolVisualData.revisionID, competencies: context.competencies)
                    }
                }
            } else if let error {
                ContentUnavailableView("Rendu indisponible", systemImage: "exclamationmark.triangle", description: Text(error))
            } else { ProgressView("Préparation du rendu…") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The tab shell shows its real tab bar: no banner over it.
            if !Self.shellScreens.contains(screen) {
                Text("Rendu de contrôle · données fictives")
                    .font(.caption2).foregroundStyle(DrivyTheme.muted)
                    .padding(.vertical, 5).frame(maxWidth: .infinity).background(DrivyTheme.surface)
            }
        }
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.environment["DRIVY_VISUAL_LARGE_TEXT"] == "1" ? .accessibility3 : systemTextSize)
        .environment(\.locale, Locale(identifier: "fr_CH"))
        .tint(DrivyTheme.accent)
        .task {
            guard context == nil else { return }
            do { context = try await SchoolVisualData.prepare() }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// The real school shell (SchoolHomeView and its tab bar). Actions are inert:
/// the capture only renders the first frame of each tab.
private struct SchoolVisualShell: View {
    let context: SchoolVisualContext
    /// Selected after the list appears, as a tap would, so a compact split view pushes the dossier.
    let learnerID: UUID?
    @State private var selectedTab: SchoolHomeTab

    init(context: SchoolVisualContext, tab: SchoolHomeTab, learnerID: UUID? = nil) {
        self.context = context
        self.learnerID = learnerID
        _selectedTab = State(initialValue: tab)
    }

    var body: some View {
        SchoolHomeView(workspace: context.workspace, localController: context.local,
            openAccount: {}, signOut: {},
            configureSchool: {}, openInvitations: {},
            openProfile: { _ in }, openProfilePolicy: {},
            openOnboarding: nil, openCatalog: {},
            openTrainingAdministration: { _ in }, agendaClient: context.agenda,
            openMembers: {}, openAddLearner: {},
            trainingClient: context.client, captureController: nil,
            selectedTab: $selectedTab)
        .task {
            guard let learnerID else { return }
            try? await Task.sleep(for: .milliseconds(500))
            context.workspace.selectLearner(learnerID)
        }
    }
}

@MainActor private struct SchoolVisualContext {
    let workspace: SchoolWorkspace
    let client: SchoolTrainingClient
    let agenda: SchoolAgendaClient
    let local: SessionController
    let catalog: SchoolCatalogWorkspace
    let learner: SchoolLearner
    let competencies: [SchoolCatalogCompetency]
}

@MainActor private enum SchoolVisualData {
    static let schoolID = identifier(1)
    static let personID = identifier(2)
    static let membershipID = identifier(3)
    static let learnerID = identifier(4)
    static let trainingID = identifier(5)
    static let offeringID = identifier(6)
    static let curriculumID = identifier(7)
    static let policyID = identifier(8)
    static let lessonID = identifier(9)
    static let revisionID = identifier(10)
    static let time = "2026-09-24T10:00:00Z"

    static func prepare() async throws -> SchoolVisualContext {
        let baseURL = URL(string: "https://visual.drivy.invalid")!
        let fixtures = try responses()
        let transport = SchoolVisualTransport(responses: fixtures)
        let token = SchoolVisualToken()
        let client = SchoolTrainingClient(baseURL: baseURL, tokenSource: token, transport: transport)
        let agenda = SchoolAgendaClient(baseURL: baseURL, tokenSource: token, transport: transport)
        let workspace = SchoolWorkspace(api: client.reader)
        await workspace.loadAccount()
        guard workspace.membership != nil, workspace.school != nil else { throw SchoolAPIError.invalidResponse }
        // Isolated, throwaway encrypted journal: no example journeys, no native location.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DrivySchoolVisual-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try SQLCipherSessionStore(url: directory.appendingPathComponent("visual.sqlite"),
            key: Data(repeating: 0xAC, count: 32), protectFiles: false)
        let local = SessionController(store: store, location: SchoolVisualLocationSource())
        let learner: SchoolLearner = try decode(learnerObject)
        let competencies: [SchoolCatalogCompetency] = try decode(competencyObjects)
        let scope = SchoolCommandScope(personID: personID, schoolID: schoolID, membershipID: membershipID,
            accessEpoch: 1, apiBaseURL: baseURL.absoluteString)
        let catalog = SchoolCatalogWorkspace(scope: scope, api: client.catalog, outbox: SchoolVisualOutbox())
        return SchoolVisualContext(workspace: workspace, client: client, agenda: agenda, local: local,
            catalog: catalog, learner: learner, competencies: competencies)
    }

    private static func identifier(_ value: Int) -> UUID {
        UUID(uuidString: "10000000-0000-4000-8000-" + String(format: "%012d", value))!
    }

    private static var learnerObject: [String: Any] {
        ["id": learnerID.uuidString, "schoolId": schoolID.uuidString, "personId": identifier(11).uuidString,
         "version": 1, "displayName": "Camille Exemple", "contactEmail": "camille@example.invalid",
         "contactPhone": NSNull(), "archivedAt": NSNull(), "profileReadiness": "READY"]
    }

    /// Fictional learners shown in lists and in the agenda; only `learnerID` has a dossier.
    private static let otherLearners: [(id: UUID, person: UUID, name: String, readiness: String)] = [
        (identifier(14), identifier(17), "Léa Exemple", "MINIMAL"),
        (identifier(15), identifier(18), "Noah Exemple", "READY"),
        (identifier(16), identifier(19), "Inès Exemple", "READY")
    ]

    private static var learnerObjects: [[String: Any]] {
        var objects: [[String: Any]] = [learnerObject]
        for learner in otherLearners {
            let object: [String: Any] = ["id": learner.id.uuidString, "schoolId": schoolID.uuidString,
                "personId": learner.person.uuidString, "version": 1, "displayName": learner.name,
                "contactEmail": NSNull(), "contactPhone": NSNull(), "archivedAt": NSNull(),
                "profileReadiness": learner.readiness]
            objects.append(object)
        }
        return objects
    }

    /// Lessons relative to the capture day (Europe/Zurich), so the agenda and the
    /// map home both show a populated day. Places are fictional labels, never coordinates.
    private static func agendaLessons() -> [[String: Any]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        let today = calendar.startOfDay(for: Date())
        let iso = ISO8601DateFormatter()
        let plan: [(day: Int, hour: Int, minute: Int, minutes: Int, learner: UUID, status: String, place: String)] = [
            (0, 8, 0, 50, learnerID, "COMPLETED", "Gare · lieu fictif"),
            (0, 10, 30, 50, otherLearners[0].id, "PLANNED", "Place du Marché · lieu fictif"),
            (0, 14, 0, 75, otherLearners[1].id, "PLANNED", "Collège · lieu fictif"),
            (0, 16, 30, 50, otherLearners[2].id, "CANCELLED", "Piscine · lieu fictif"),
            (1, 9, 0, 50, learnerID, "PLANNED", "Gare · lieu fictif"),
            (2, 13, 30, 50, otherLearners[0].id, "PLANNED", "Place du Marché · lieu fictif")
        ]
        var result: [[String: Any]] = []
        for (index, item) in plan.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: item.day, to: today),
                  let start = calendar.date(bySettingHour: item.hour, minute: item.minute, second: 0, of: day) else { continue }
            let end = start.addingTimeInterval(TimeInterval(item.minutes * 60))
            let actualStart: Any
            let actualEnd: Any
            if item.status == "COMPLETED" {
                actualStart = iso.string(from: start)
                actualEnd = iso.string(from: end)
            } else {
                actualStart = NSNull()
                actualEnd = NSNull()
            }
            let object: [String: Any] = ["id": identifier(40 + index).uuidString, "schoolId": schoolID.uuidString, "version": 1,
                "trainingId": trainingID.uuidString, "learnerId": item.learner.uuidString,
                "instructorMembershipId": membershipID.uuidString,
                "plannedStart": iso.string(from: start), "plannedEnd": iso.string(from: end),
                "timeZone": "Europe/Zurich", "meetingPoint": item.place, "status": item.status,
                "priceCentsSnapshot": 9500, "bufferMinutesSnapshot": 10,
                "actualStart": actualStart, "actualEnd": actualEnd, "permitWarning": false,
                "publicationVersion": 0, "currentPublishedRevisionId": NSNull(), "commercialRevisionVersion": 1]
            result.append(object)
        }
        return result
    }

    private static var competencyObjects: [[String: Any]] {
        [
            ("Priorités", "Observer et aborder les intersections.", "priorities"),
            ("Stationnement", "Choisir les repères et contrôler l’environnement.", "parking"),
            ("Autoroute", "Préparer l’insertion et adapter les distances.", "motorway")
        ].enumerated().map { index, value in
            ["id": identifier(30 + index).uuidString, "schoolId": schoolID.uuidString, "version": 1,
             "curriculumVersionId": curriculumID.uuidString, "key": value.2,
             "label": value.0, "description": value.1, "sortOrder": index]
        }
    }

    private static func responses() throws -> [String: Data] {
        let null = NSNull()
        let root = "/v1/schools/\(schoolID.uuidString)"
        let roles = ["ADMIN", "INSTRUCTOR"]
        let membership: [String: Any] = ["membershipId": membershipID.uuidString, "schoolId": schoolID.uuidString,
            "schoolName": "École Exemple", "roles": roles, "grants": [], "accessEpoch": 1]
        let person: [String: Any] = ["personId": personID.uuidString, "version": 1,
            "displayName": "Moniteur Exemple", "locale": "fr-CH", "memberships": [membership]]
        let school: [String: Any] = ["id": schoolID.uuidString, "schoolId": schoolID.uuidString,
            "version": 1, "name": "École Exemple", "timeZone": "Europe/Zurich", "status": "ACTIVE",
            "contactEmail": "contact@example.invalid", "contactPhone": null, "logoAssetId": null,
            "modules": ["gpsEnabled": true, "packsEnabled": false, "collectiveCoursesEnabled": false,
                "courseOffersVisibleByDefault": false], "configurationVersion": 1]
        let training: [String: Any] = ["id": trainingID.uuidString, "schoolId": schoolID.uuidString,
            "learnerId": learnerID.uuidString, "offeringId": offeringID.uuidString, "version": 1,
            "categoryCode": "B", "status": "ACTIVE", "startedOn": "2026-09-01", "closedOn": null]
        let offering: [String: Any] = ["id": offeringID.uuidString, "schoolId": schoolID.uuidString,
            "version": 2, "offeringKey": "Conduite accompagnée", "categoryCode": "B",
            "curriculumVersionId": curriculumID.uuidString, "policyVersionId": policyID.uuidString,
            "enabled": true, "defaultDurationMinutes": 50, "defaultPriceCents": 9500]
        var otherOffering = offering
        otherOffering["id"] = identifier(12).uuidString
        otherOffering["offeringKey"] = "Manœuvres et préparation à la circulation"
        otherOffering["defaultDurationMinutes"] = 75
        otherOffering["defaultPriceCents"] = 14000
        otherOffering["enabled"] = false
        let curriculum: [String: Any] = ["id": curriculumID.uuidString, "schoolId": schoolID.uuidString,
            "version": 1, "categoryCode": "B", "revision": 2, "approved": true, "competencies": competencyObjects]
        let policy: [String: Any] = ["id": policyID.uuidString, "schoolId": schoolID.uuidString, "version": 1,
            "categoryCode": "B", "procedureText": "Texte fictif : préparation, conduite et bilan de la leçon.",
            "cancellationPolicyText": "Conditions fictives destinées au contrôle de la mise en page.",
            "sourceUrls": [], "approved": true, "approvedAt": time]
        let member: [String: Any] = ["id": membershipID.uuidString, "schoolId": schoolID.uuidString, "version": 1,
            "personId": personID.uuidString, "displayName": "Moniteur Exemple", "status": "ACTIVE",
            "roles": roles, "grants": [], "accessEpoch": 1]
        let lesson: [String: Any] = ["id": lessonID.uuidString, "schoolId": schoolID.uuidString, "version": 1,
            "trainingId": trainingID.uuidString, "learnerId": learnerID.uuidString,
            "instructorMembershipId": membershipID.uuidString, "plannedStart": "2026-09-21T07:00:00Z",
            "plannedEnd": "2026-09-21T07:50:00Z", "timeZone": "Europe/Zurich", "meetingPoint": "Gare de Cernier · exemple",
            "status": "COMPLETED", "priceCentsSnapshot": 9500, "bufferMinutesSnapshot": 10,
            "actualStart": "2026-09-21T07:00:00Z", "actualEnd": "2026-09-21T07:50:00Z",
            "permitWarning": false, "publicationVersion": 1, "currentPublishedRevisionId": revisionID.uuidString,
            "commercialRevisionVersion": 1]
        var nextLesson = lesson
        nextLesson["id"] = identifier(13).uuidString
        nextLesson["plannedStart"] = "2026-09-28T08:00:00Z"
        nextLesson["plannedEnd"] = "2026-09-28T08:50:00Z"
        nextLesson["actualStart"] = null; nextLesson["actualEnd"] = null
        nextLesson["status"] = "PLANNED"
        nextLesson["publicationVersion"] = 0; nextLesson["currentPublishedRevisionId"] = null
        let observation: [String: Any] = ["competencyId": identifier(30).uuidString, "level": "GUIDED",
            "context": "Intersections en zone urbaine, avec rappel des contrôles latéraux."]
        let revision: [String: Any] = ["id": revisionID.uuidString, "schoolId": schoolID.uuidString,
            "lessonId": lessonID.uuidString, "authorMembershipId": membershipID.uuidString, "version": 1,
            "sequence": 1, "publishedAt": "2026-09-21T08:00:00Z",
            "workedOn": "Priorités à droite et choix de la vitesse à l’approche des intersections.",
            "observationText": "Les contrôles sont réguliers. Prendre plus tôt les informations latérales permet de décider sans précipitation.",
            "nextStep": "Reprendre les priorités à droite sur un trajet moins familier, puis travailler le stationnement.",
            "observations": [observation], "attachmentIds": [], "correctionReason": null,
            "capturePublication": null, "textObservations": []]
        let progressItem: [String: Any] = ["competencyId": identifier(30).uuidString, "sourceLessonId": lessonID.uuidString,
            "sourceRevisionId": revisionID.uuidString, "label": "Priorités", "level": "GUIDED",
            "context": "Intersections en zone urbaine", "observedAt": "2026-09-21T07:50:00Z"]
        let progress: [String: Any] = ["trainingId": trainingID.uuidString, "items": [progressItem],
            "unobservedCompetencyIds": [identifier(31).uuidString, identifier(32).uuidString], "computedAt": time]
        let agendaKey = "\(root)/lessons" + SchoolVisualTransport.agendaSuffix
        let objects: [String: Any] = [
            "/v1/me": person, root: school,
            "\(root)/learners": page(learnerObjects), "\(root)/learners/\(learnerID.uuidString)": learnerObject,
            "\(root)/trainings": page([training]), "\(root)/trainings/\(trainingID.uuidString)": training,
            "\(root)/trainings/\(trainingID.uuidString)/progress": progress,
            "\(root)/offerings": page([offering, otherOffering]), "\(root)/curricula": page([curriculum]),
            "\(root)/policy-versions": page([policy]), "\(root)/members": page([member]),
            "\(root)/lessons": page([nextLesson, lesson]),
            agendaKey: page(agendaLessons()), "\(root)/lessons/\(lessonID.uuidString)": lesson,
            "\(root)/lessons/\(identifier(13).uuidString)": nextLesson,
            "\(root)/report-revisions/\(revisionID.uuidString)": revision,
            "\(root)/lessons/\(lessonID.uuidString)/reports": page([revision])
        ]
        return try objects.mapValues { object in
            try JSONSerialization.data(withJSONObject: ["data": object, "requestId": identifier(99).uuidString, "serverTime": time])
        }
    }

    private static func page(_ items: [[String: Any]]) -> [String: Any] { ["items": items, "nextCursor": NSNull()] }
    private static func decode<Value: Decodable>(_ object: Any) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

private struct SchoolVisualTransport: SchoolHTTPTransport {
    /// Agenda reads (`from`/`to` window) get day-relative lessons; dossier reads keep the fixed history.
    static let agendaSuffix = "?agenda-window"
    let responses: [String: Data]
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "visual.drivy.invalid", (request.httpMethod ?? "GET") == "GET"
        else { throw SchoolAPIError.invalidResponse }
        let window = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "from" } == true
        guard let bytes = (window ? responses[url.path + Self.agendaSuffix] : nil) ?? responses[url.path]
        else { throw SchoolAPIError.invalidResponse }
        return SchoolHTTPResponse(data: bytes, status: 200, url: url, contentType: "application/json")
    }
}

@MainActor private final class SchoolVisualLocationSource: LocationSource {
    var permission: LocationPermission { .allowed }
    var onEvent: (@MainActor (LocationEvent) -> Void)?
    func requestPermission() { }
    func start() { }
    func stop() { }
}

@MainActor private final class SchoolVisualToken: AccessTokenSource {
    func accessToken() async throws -> String { "visual-fixture-only" }
}

@MainActor private final class SchoolVisualOutbox: SchoolCommandOutbox {
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { nil }
    func save(_ command: PendingSchoolCommand) throws { throw SchoolConfigurationFailure.storage }
    func remove(_ command: PendingSchoolCommand) throws { throw SchoolConfigurationFailure.storage }
}
#endif
