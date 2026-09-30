#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Actual school screens using an isolated, read-only in-memory transport.
/// No production credentials, persistent school store or network transport is created.
struct SchoolVisualReview: View {
    /// Shell screens routed here directly by DrivyApp, with the real tab bar.
    static let shellScreens: Set<String> = ["home-tabs", "agenda", "learners", "learner", "profile-tab", "learner-home", "learner-progress"]

    let screen: String
    @State private var context: SchoolVisualContext?
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var systemTextSize

    var body: some View {
        VStack(spacing: 0) {
          Group {
            if SchoolAccountVisualReview.screenNames.contains(screen) {
                SchoolAccountVisualReview(screen: screen)
            } else if let context {
                switch screen {
                case "gps-choice", "signal", "observations", "capture-preparation", "live", "live-waiting":
                    SchoolFieldVisualReview(screen: screen, context: context)
                case "planning", "start-now", "planning-settings", "invitations", "invitation-create", "invitation-detail", "lesson-tariff", "lesson-finish", "lesson-modal":
                    SchoolOfficeVisualReview(screen: screen, context: context)
                case "lesson", "lesson-planned", "lesson-observations":
                    NavigationStack {
                        SchoolLessonReportView(client: context.agenda.reportClient, schoolWorkspace: context.workspace,
                            lessonID: screen == "lesson-planned" ? SchoolVisualData.plannedLessonID : SchoolVisualData.lessonID,
                            learnerName: context.learner.displayName, outbox: SchoolVisualOutbox())
                    }
                case "invitation-code":
                    NavigationStack {
                        InvitationCodeResultView(issued: SchoolIssuedInvitationCode(invitationID: SchoolVisualData.lessonID,
                            code: "EXEM-PLE1", expiresAt: "2026-10-06T10:00:00Z"), schoolName: "École Exemple",
                            now: SchoolLesson.date("2026-09-29T10:00:00Z")!)
                            .navigationTitle("Inviter un élève")
                    }
                case "progression":
                    NavigationStack {
                        SchoolTrainingScreen(client: context.client, workspace: context.workspace,
                            learner: context.learner, trainingID: SchoolVisualData.trainingID, section: .progress)
                            .navigationTitle("Progression")
                    }
                case "trips":
                    NavigationStack {
                        SchoolTripsView(workspace: context.workspace, agendaClient: context.agenda, showsHeading: false) { EmptyView() }
                            .navigationTitle("Trajets")
                    }
                case "profile-tab":
                    SchoolVisualShell(context: context, tab: .profile)
                case "learner-home":
                    SchoolVisualShell(context: context, tab: .lessons)
                case "learner-progress":
                    SchoolVisualShell(context: context, tab: .progress)
                case "school-choice":
                    SchoolChooserSheet(workspace: context.workspace, close: {})
                case "no-school":
                    NavigationStack {
                        SchoolWithoutSchoolView(joinSchool: {})
                            .navigationTitle("Drivy")
                    }
                case "replay":
                    SchoolCaptureReplayView(model: context.replay, learnerName: "Trajet synthétique")
                case "home-tabs":
                    SchoolVisualShell(context: context, tab: .session)
                case "agenda":
                    SchoolVisualShell(context: context, tab: .agenda)
                case "learners":
                    SchoolVisualShell(context: context, tab: .learners)
                case "learner":
                    SchoolVisualShell(context: context, tab: .learners, learnerID: SchoolVisualData.learnerID)
                default:
                    SchoolTrainingView(client: context.client, workspace: context.workspace,
                        learner: context.learner, trainingID: SchoolVisualData.trainingID)
                }
            } else if let error {
                ContentUnavailableView("Rendu indisponible", systemImage: "exclamationmark.triangle", description: Text(error))
            } else { ProgressView("Préparation du rendu…") }
          }
            // The tab shell shows its real tab bar: no banner over it.
            if !Self.shellScreens.contains(screen) {
                Text(screen == "replay" ? "Rendu de contrôle · coordonnées synthétiques" : "Rendu de contrôle · données fictives")
                    .font(.caption2).foregroundStyle(DrivyTheme.muted)
                    .padding(.vertical, 5).frame(maxWidth: .infinity).background(DrivyTheme.surface)
            }
        }
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.environment["DRIVY_VISUAL_LARGE_TEXT"] == "1" ? .accessibility3 : systemTextSize)
        .environment(\.locale, Locale(identifier: "fr_CH"))
        .tint(DrivyTheme.accent)
        .task {
            guard !SchoolAccountVisualReview.screenNames.contains(screen) else { return }
            guard context == nil else { return }
            do {
                context = try await SchoolVisualData.prepare(learnerRole: screen == "learner-home" || screen == "learner-progress",
                    populatedObservations: screen == "lesson-observations")
            }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// The real school shell (SchoolHomeView and its tab bar). Actions are inert:
/// the capture only renders the first frame of each tab. « trips » shows the Profil tab: account, then trips.
struct SchoolVisualShell: View {
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
        SchoolHomeView(workspace: context.workspace, openAccount: {},
            account: SchoolAccountActions(manageURL: nil, openProfile: nil, openInvitations: {}, openJoinSchool: {}, signOut: {}),
            inviteLearner: {},
            openProfile: { _ in }, agendaClient: context.agenda,
            trainingClient: context.client, captureController: nil,
            selectedTab: $selectedTab)
        .task {
            guard let learnerID else { return }
            try? await Task.sleep(for: .milliseconds(500))
            context.workspace.selectLearner(learnerID)
        }
    }
}

@MainActor struct SchoolVisualContext {
    let workspace: SchoolWorkspace
    let client: SchoolTrainingClient
    let agenda: SchoolAgendaClient
    let learner: SchoolLearner
    let replay: SchoolCaptureReplayWorkspace
}

@MainActor enum SchoolVisualData {
    nonisolated static let schoolID = identifier(1)
    nonisolated static let personID = identifier(2)
    nonisolated static let membershipID = identifier(3)
    nonisolated static let learnerID = identifier(4)
    nonisolated static let trainingID = identifier(5)
    nonisolated static let offeringID = identifier(6)
    nonisolated static let curriculumID = identifier(7)
    nonisolated static let policyID = identifier(8)
    nonisolated static let lessonID = identifier(9)
    nonisolated static let revisionID = identifier(10)
    nonisolated static let plannedLessonID = identifier(13)
    nonisolated static let captureID = identifier(70)
    nonisolated static let time = "2026-09-24T10:00:00Z"

    static func prepare(learnerRole: Bool = false, populatedObservations: Bool = false) async throws -> SchoolVisualContext {
        let baseURL = URL(string: "https://visual.drivy.invalid")!
        let fixtures = try responses(learnerRole: learnerRole, populatedObservations: populatedObservations)
        let transport = SchoolVisualTransport(responses: fixtures)
        let token = SchoolVisualToken()
        let client = SchoolTrainingClient(baseURL: baseURL, tokenSource: token, transport: transport)
        let agenda = SchoolAgendaClient(baseURL: baseURL, tokenSource: token, transport: transport)
        let workspace = SchoolWorkspace(api: client.reader)
        await workspace.loadAccount()
        guard let person = workspace.person, let membership = workspace.membership, workspace.school != nil else { throw SchoolAPIError.invalidResponse }
        let learner: SchoolLearner = try decode(learnerObject)
        let replay = SchoolCaptureReplayWorkspace(scope: agenda.scope(person: person, membership: membership),
            client: agenda.captureClient, captureID: captureID)
        return SchoolVisualContext(workspace: workspace, client: client, agenda: agenda,
            learner: learner, replay: replay)
    }

    nonisolated private static func identifier(_ value: Int) -> UUID {
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
            ("Priorités", "Priorité de droite, signalisation et céder le passage.", "priorites"),
            ("Stationnement", "Choisir les repères et contrôler l’environnement.", "parking"),
            ("Autoroute", "Préparer l’insertion et adapter les distances.", "motorway"),
            ("Adaptation de la vitesse", "Vitesse adaptée aux limites, à la visibilité et au trafic.", "vitesse"),
            ("Anticipation", "Préparer les situations de conduite.", "anticipation")
        ].enumerated().map { index, value in
            ["id": identifier(30 + index).uuidString, "schoolId": schoolID.uuidString, "version": 1,
             "curriculumVersionId": curriculumID.uuidString, "key": value.2,
             "label": value.0, "description": value.1, "sortOrder": index]
        }
    }

    /// Deliberately geometric paths around 0° / 0° in the ocean, generated here.
    /// These DEBUG-only coordinates do not represent a learner, road or GPS recording.
    private static func syntheticCapture(_ id: UUID) -> [String: Any] {
        ["id": id.uuidString, "schoolId": schoolID.uuidString, "version": 1,
         "lessonId": lessonID.uuidString, "learnerId": learnerID.uuidString,
         "instructorMembershipId": membershipID.uuidString, "deviceId": identifier(73).uuidString,
         "choiceId": identifier(74).uuidString, "deviceAssessmentId": identifier(75).uuidString,
         "authorizedAt": "2026-09-21T07:00:00Z", "expiresAt": "2026-09-21T10:00:00Z",
         "stoppedAt": "2026-09-21T07:02:20Z", "cutoffAt": "2026-09-21T07:02:20Z",
         "uploadDeadline": "2026-09-22T10:00:00Z", "captureState": "STOPPED",
         "syncState": "SYNCED", "publicationState": "PRIVATE"]
    }

    private static func syntheticTrips() -> [[String: Any]] {
        [captureID, identifier(71), identifier(72)].enumerated().map { index, id in
            var capture = syntheticCapture(id)
            capture["learnerName"] = ["Camille Exemple", "Léa Exemple", "Noah Exemple"][index]
            capture["instructorName"] = "Moniteur Exemple"
            capture["lessonPlannedStart"] = "2026-09-21T07:00:00Z"
            capture["lessonTimeZone"] = "Europe/Zurich"
            if index == 1 { capture["syncState"] = "PARTIAL" }
            if index == 2 { capture["publicationState"] = "DELETED" }
            return capture
        }
    }

    private static func syntheticReplay() -> [String: Any] {
        let origin = SchoolLesson.date("2026-09-21T07:00:00Z")!
        let iso = ISO8601DateFormatter()
        let segments: [[String: Any]] = (0..<2).map { segmentIndex in
            let points: [[String: Any]] = (0..<7).map { index in
                let seconds = segmentIndex * 80 + index * 10
                return ["sequence": index, "elapsedMs": seconds * 1000,
                    "capturedAt": iso.string(from: origin.addingTimeInterval(Double(seconds))),
                    "latitude": Double(segmentIndex) * 0.004 + Double(index) * 0.0004,
                    "longitude": Double(index) * 0.0007,
                    "accuracyMeters": 5.0]
            }
            return ["segmentId": identifier(76 + segmentIndex).uuidString, "segmentIndex": segmentIndex,
                "points": points, "hasGapBefore": segmentIndex > 0, "qualityLabel": "AVAILABLE",
                "continuesFromPreviousPage": false, "continuesOnNextPage": false]
        }
        let observations: [[String: Any]] = (0..<3).map { index in
            let segment = index == 2 ? 1 : 0
            let sequence = index == 1 ? 5 : 2
            let seconds = segment * 80 + sequence * 10
            var observation: [String: Any] = ["id": identifier(80 + index).uuidString, "schoolId": schoolID.uuidString,
                "version": 1, "lessonId": lessonID.uuidString, "trainingId": trainingID.uuidString,
                "captureId": captureID.uuidString, "segmentId": identifier(76 + segment).uuidString,
                "pointSequence": sequence, "competencyId": identifier(30).uuidString,
                "text": ["Contrôle latéral · exemple", "Moment à revoir · exemple", "Bonne anticipation · exemple"][index],
                "origin": "LIVE", "observedAt": iso.string(from: origin.addingTimeInterval(Double(seconds))),
                "eventKind": index == 1 ? "MARKER" : "QUALIFIED",
                "eventStatus": index == 0 ? "ATTENTION" : "POSITIVE",
                "authorMembershipId": membershipID.uuidString]
            if index == 1 { observation["competencyId"] = NSNull(); observation["eventStatus"] = NSNull() }
            return observation
        }
        return ["captureId": captureID.uuidString, "quality": "SYNCED", "publicationState": "PRIVATE",
            "segments": segments, "observations": observations, "nextCursor": NSNull(),
            "generatedAt": time, "reportRevisionId": NSNull(), "geometrySnapshotId": NSNull()]
    }

    static func responses(learnerRole: Bool = false, populatedObservations: Bool = false) throws -> [String: Data] {
        let null = NSNull()
        let root = "/v1/schools/\(schoolID.uuidString)"
        let roles = ["ADMIN", "INSTRUCTOR"]
        let membership: [String: Any] = ["membershipId": membershipID.uuidString, "schoolId": schoolID.uuidString,
            "schoolName": "École Exemple", "roles": learnerRole ? ["LEARNER"] : roles, "grants": [], "accessEpoch": 1]
        let person: [String: Any] = ["personId": (learnerRole ? identifier(11) : personID).uuidString, "version": 1,
            "displayName": learnerRole ? "Camille Exemple" : "Moniteur Exemple", "locale": "fr-CH", "memberships": [membership]]
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
        var objects: [String: Any] = [
            "/v1/me": person, root: school,
            "\(root)/planning-defaults": ["id": membershipID.uuidString, "schoolId": schoolID.uuidString,
                "version": 1, "trainingCategoryCode": NSNull(), "serviceProductKey": NSNull()],
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
        objects["\(root)/recording-notice"] = ["noticeVersionId": identifier(91).uuidString,
            "noticeText": "Document de contrôle : le trajet sert à revoir la leçon avec l’élève et son moniteur. Les positions ne sont pas publiques.",
            "retentionText": "Document de contrôle : la durée de conservation et les modalités d’effacement sont fixées par l’école.",
            "contactEmail": "contact@example.invalid", "approvedAt": time]
        objects["\(root)/learners/\(learnerID.uuidString)/recording-choice"] = ["id": identifier(92).uuidString,
            "schoolId": schoolID.uuidString, "version": 1, "learnerId": learnerID.uuidString, "lessonId": null,
            "status": "UNKNOWN", "noticeVersionId": identifier(91).uuidString, "recordedBy": membershipID.uuidString,
            "recordedAt": time, "source": "RECORDED_VERBAL"]
        objects["\(root)/captures"] = page(syntheticTrips())
        objects["\(root)/captures/\(captureID.uuidString)"] = syntheticCapture(captureID)
        objects["\(root)/captures/\(captureID.uuidString)/replay"] = syntheticReplay()
        var draft = revision
        draft["id"] = identifier(60).uuidString
        draft["basePublicationVersion"] = 1
        draft["geoObservationIds"] = [] as [Any]
        objects["\(root)/lessons/\(lessonID.uuidString)/report-drafts"] = page([draft])
        objects["\(root)/lessons/\(lessonID.uuidString)/sharing"] = ["lessonId": lessonID.uuidString,
            "schoolId": schoolID.uuidString, "version": 1, "reportPrivate": false, "captureHidden": false,
            "privateObservationIds": [] as [Any]]
        objects["\(root)/lessons/\(lessonID.uuidString)/account"] = ["id": identifier(64).uuidString,
            "ownerId": lessonID.uuidString, "ownerType": "LESSON", "lessonId": lessonID.uuidString, "version": 1,
            "currency": "CHF", "plannedPriceCents": 9500, "chargeCents": 9500, "netReceivedCents": 0,
            "balanceCents": 9500, "charges": [] as [Any]]
        objects["\(root)/trainings/\(trainingID.uuidString)/wish"] = ["id": identifier(61).uuidString,
            "schoolId": schoolID.uuidString, "trainingId": trainingID.uuidString, "version": 1, "lessonId": null,
            "text": "Revoir les priorités à droite."]
        for id in [lessonID, plannedLessonID] {
            objects["\(root)/lessons/\(id.uuidString)/preparation"] = ["id": identifier(id == lessonID ? 62 : 63).uuidString,
                "schoolId": schoolID.uuidString, "lessonId": id.uuidString, "version": 1,
                "goals": [["label": "Anticiper les intersections", "competencyId": identifier(30).uuidString, "context": null]],
                "administrativeCheckNote": null, "plannedWaypoints": [] as [Any]]
            let observations: [[String: Any]] = populatedObservations ? (0..<3).map { index in
                ["id": identifier(110 + index).uuidString, "schoolId": schoolID.uuidString, "version": 1,
                 "lessonId": id.uuidString, "trainingId": trainingID.uuidString,
                 "captureId": null, "segmentId": null, "pointSequence": null,
                 "competencyId": identifier(30 + index).uuidString,
                 "text": ["Priorité à droite · regard tardif", "Stationnement · contrôle de l’angle mort", "Insertion · bonne anticipation"][index],
                 "origin": "LIVE", "observedAt": "\(id == lessonID ? "2026-09-21T07" : "2026-09-28T08"):\(10 + index * 10):00Z",
                 "eventKind": "QUALIFIED", "eventStatus": ["TO_REWORK", "ATTENTION", "POSITIVE"][index],
                 "authorMembershipId": membershipID.uuidString]
            } : []
            objects["\(root)/lessons/\(id.uuidString)/geo-observations"] = page(observations)
            objects["\(root)/lessons/\(id.uuidString)/captures"] = ["items": [] as [Any]]
        }
        objects["\(root)/lessons/\(lessonID.uuidString)/captures"] = ["items": [syntheticCapture(captureID)]]
        objects["\(root)/lessons/\(plannedLessonID.uuidString)/reports"] = page([])
        return try objects.mapValues { object in
            try JSONSerialization.data(withJSONObject: ["data": object, "requestId": identifier(99).uuidString, "serverTime": time])
        }
    }

    private static func page(_ items: [[String: Any]]) -> [String: Any] { ["items": items, "nextCursor": NSNull()] }
    private static func decode<Value: Decodable>(_ object: Any) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

struct SchoolVisualTransport: SchoolHTTPTransport {
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

@MainActor final class SchoolVisualToken: AccessTokenSource {
    func accessToken() async throws -> String { "visual-fixture-only" }
}

@MainActor final class SchoolVisualOutbox: SchoolCommandOutbox {
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { nil }
    func save(_ command: PendingSchoolCommand) throws { throw SchoolConfigurationFailure.storage }
    func remove(_ command: PendingSchoolCommand) throws { throw SchoolConfigurationFailure.storage }
}

#endif
