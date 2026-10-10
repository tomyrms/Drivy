#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Actual school screens using an isolated, read-only in-memory transport.
/// No production credentials, persistent school store or network transport is created.
struct SchoolVisualReview: View {
    /// Shell screens routed here directly by DrivyApp, with the real tab bar.
    static let shellScreens: Set<String> = ["home-tabs", "home-to-finish", "agenda", "learners", "learner", "dossier", "profile-tab", "learner-home", "learner-progress", "live", "live-waiting", "dossier-multi"]

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
                case "planning", "start-now", "planning-settings", "invitations", "invitation-create", "invitation-detail", "lesson-tariff", "lesson-finish", "lesson-modal", "lesson-permit":
                    SchoolOfficeVisualReview(screen: screen, context: context)
                case "lesson", "lesson-planned", "lesson-observations", "lesson-cancelled":
                    NavigationStack {
                        SchoolLessonReportView(client: context.agenda.reportClient, schoolWorkspace: context.workspace,
                            lessonID: SchoolVisualData.reportLessonID(for: screen),
                            learnerName: context.learner.displayName, outbox: SchoolVisualOutbox())
                    }
                case "invitation-code":
                    NavigationStack {
                        InvitationCodeResultView(issued: SchoolIssuedInvitationCode(invitationID: SchoolVisualData.lessonID,
                            code: "K7QM-4TXR", expiresAt: "2026-10-06T10:00:00Z"), schoolName: "Auto-école du Val-de-Ruz",
                            now: SchoolLesson.date("2026-09-29T10:00:00Z")!)
                            .navigationTitle("Inviter un élève")
                    }
                case "lessons-multi", "lessons-two", "progression-multi":
                    NavigationStack {
                        SchoolVisualTrainingPage(context: context, permitCount: SchoolVisualData.permitCount(for: screen),
                            section: screen == "progression-multi" ? .progress : .lessons)
                            .navigationTitle(screen == "progression-multi" ? "Progression" : "Leçons")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                case "progression":
                    NavigationStack {
                        SchoolTrainingScreen(client: context.client, workspace: context.workspace,
                            learner: context.learner, trainingID: SchoolVisualData.trainingID, section: .progress)
                            .navigationTitle("Progression")
                    }
                case "lessons-history":
                    NavigationStack {
                        SchoolLessonHistoryView(workspace: context.workspace, agendaClient: context.agenda)
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
                    SchoolCaptureReplayView(model: context.replay, learnerName: "Trajet synthétique", lessonTimeZone: "Europe/Zurich")
                case "home-tabs", "home-to-finish":
                    SchoolVisualShell(context: context, tab: .session)
                case "agenda":
                    SchoolVisualShell(context: context, tab: .agenda)
                case "learners":
                    SchoolVisualShell(context: context, tab: .learners)
                case "learner", "dossier", "dossier-multi":
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
                    populatedObservations: screen == "lesson-observations",
                    permitCount: SchoolVisualData.permitCount(for: screen))
            }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// The real school shell, with isolated navigation into the welcome fixture.
/// School writes and account actions remain inert.
struct SchoolVisualShell: View {
    let context: SchoolVisualContext
    /// Selected after the list appears, as a tap would, so a compact split view pushes the dossier.
    let learnerID: UUID?
    @State private var selectedTab: SchoolHomeTab
    @State private var showsWelcome = false

    init(context: SchoolVisualContext, tab: SchoolHomeTab, learnerID: UUID? = nil) {
        self.context = context
        self.learnerID = learnerID
        _selectedTab = State(initialValue: tab)
    }

    var body: some View {
        SchoolHomeView(workspace: context.workspace, openAccount: {},
            account: SchoolAccountActions(manageURL: nil, openProfile: nil, openInvitations: {}, openJoinSchool: {}, signOut: {},
                resumeOnboarding: { showsWelcome = true }),
            inviteLearner: {},
            openProfile: { _ in }, makeLearnerProfile: { context.makeLearnerProfile($0) },
            agendaClient: context.agenda, trainingClient: context.client, captureController: nil,
            selectedTab: $selectedTab)
        .sheet(isPresented: $showsWelcome) {
            SchoolAccountVisualReview(screen: "onboarding-staff")
        }
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
    let profile: SchoolProfileClient
    let agenda: SchoolAgendaClient
    let learner: SchoolLearner
    let replay: SchoolCaptureReplayWorkspace

    func makeLearnerProfile(_ learner: SchoolLearner) -> SchoolProfileWorkspace? {
        guard let person = workspace.person, let membership = workspace.membership,
              membership.schoolId == learner.schoolId else { return nil }
        return SchoolProfileWorkspace(scope: agenda.scope(person: person, membership: membership),
            roles: membership.roles, learnerID: learner.id, isOwnProfile: learner.personId == person.personId,
            api: profile, outbox: SchoolVisualOutbox())
    }
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

    static func prepare(learnerRole: Bool = false, populatedObservations: Bool = false,
        permitCount: Int = 1) async throws -> SchoolVisualContext {
        let baseURL = URL(string: "https://visual.drivy.invalid")!
        let fixtures = try responses(learnerRole: learnerRole, populatedObservations: populatedObservations,
            permitCount: permitCount)
        let transport = SchoolVisualTransport(responses: fixtures)
        let token = SchoolVisualToken()
        let client = SchoolTrainingClient(baseURL: baseURL, tokenSource: token, transport: transport)
        let profile = SchoolProfileClient(baseURL: baseURL, tokenSource: token, transport: transport)
        let agenda = SchoolAgendaClient(baseURL: baseURL, tokenSource: token, transport: transport)
        let workspace = SchoolWorkspace(api: client.reader)
        await workspace.loadAccount()
        guard let person = workspace.person, let membership = workspace.membership, workspace.school != nil else { throw SchoolAPIError.invalidResponse }
        let learner: SchoolLearner = try decode(learnerObject)
        let replay = SchoolCaptureReplayWorkspace(scope: agenda.scope(person: person, membership: membership),
            client: agenda.captureClient, captureID: captureID)
        return SchoolVisualContext(workspace: workspace, client: client, profile: profile, agenda: agenda,
            learner: learner, replay: replay)
    }

    nonisolated static func identifier(_ value: Int) -> UUID {
        UUID(uuidString: "10000000-0000-4000-8000-" + String(format: "%012d", value))!
    }

    private static var learnerObject: [String: Any] {
        ["id": learnerID.uuidString, "schoolId": schoolID.uuidString, "personId": identifier(11).uuidString,
         "version": 1, "displayName": "Camille Perret", "contactEmail": "camille@example.invalid",
         "contactPhone": NSNull(), "archivedAt": NSNull(), "profileReadiness": "READY"]
    }

    /// Fictional learners shown in lists and in the agenda; only `learnerID` has a dossier.
    private static let otherLearners: [(id: UUID, person: UUID, name: String, readiness: String)] = [
        (identifier(14), identifier(17), "Léa Morel", "MINIMAL"),
        (identifier(15), identifier(18), "Noah Jacot", "READY"),
        (identifier(16), identifier(19), "Inès Dubois", "READY")
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
            (0, 8, 0, 50, learnerID, "COMPLETED", "Gare de Cernier"),
            (0, 10, 30, 50, otherLearners[0].id, "PLANNED", "Place du Marché, Fontainemelon"),
            (0, 14, 0, 75, otherLearners[1].id, "PLANNED", "Collège de la Fontenelle"),
            (0, 16, 30, 50, otherLearners[2].id, "CANCELLED", "Piscine d’Engollon"),
            (1, 9, 0, 50, learnerID, "PLANNED", "Gare de Cernier"),
            (2, 13, 30, 50, otherLearners[0].id, "PLANNED", "Place du Marché, Fontainemelon")
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
        if ProcessInfo.processInfo.environment["DRIVY_VISUAL_SCREEN"] == "home-to-finish" {
            // A started lesson awaiting completion and two upcoming ones, independently of the runner's hour.
            // Only the isolated visual transport receives these synthetic lesson times.
            let now = Date()
            for (index, minutes) in [-90, 45, 150].enumerated() {
                let start = now.addingTimeInterval(TimeInterval(minutes * 60))
                result[index]["plannedStart"] = iso.string(from: start)
                result[index]["plannedEnd"] = iso.string(from: start.addingTimeInterval(50 * 60))
                result[index]["status"] = "PLANNED"
                result[index]["actualStart"] = index == 0 ? iso.string(from: start) as Any : NSNull()
                result[index]["actualEnd"] = NSNull()
            }
        }
        return result
    }

    private static var competencyObjects: [[String: Any]] {
        [
            ("Priorités", "Priorité de droite, signalisation et céder le passage.", "priorites"),
            ("Stationnement", "Choisir les repères et contrôler l’environnement.", "parking"),
            ("Autoroute", "Préparer l’insertion et adapter les distances.", "motorway"),
            ("Adaptation de la vitesse", "Vitesse adaptée aux limites, à la visibilité et au trafic.", "vitesse"),
            ("Anticipation", "Préparer les situations de conduite.", "anticipation"),
            ("Maîtrise du véhicule", "Démarrer, s’arrêter et diriger.", "vehicule"),
            ("Observation et contrôles", "Rétroviseurs et angles morts.", "observation"),
            ("Intersections et giratoires", "Choix de voie, placement et sortie.", "intersections"),
            ("Placement sur la chaussée", "Position dans la voie et les virages.", "placement")
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
            capture["learnerName"] = ["Camille Perret", "Léa Morel", "Noah Jacot"][index]
            capture["instructorName"] = "Julien Rey"
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
                "text": ["Contrôle latéral", "Moment à revoir", "Bonne anticipation"][index],
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

    static func responses(learnerRole: Bool = false, populatedObservations: Bool = false,
        permitCount: Int = 1) throws -> [String: Data] {
        let null = NSNull()
        let root = "/v1/schools/\(schoolID.uuidString)"
        let roles = ["ADMIN", "INSTRUCTOR"]
        let membership: [String: Any] = ["membershipId": membershipID.uuidString, "schoolId": schoolID.uuidString,
            "schoolName": "Auto-école du Val-de-Ruz", "roles": learnerRole ? ["LEARNER"] : roles, "grants": [], "accessEpoch": 1]
        let person: [String: Any] = ["personId": (learnerRole ? identifier(11) : personID).uuidString, "version": 1,
            "displayName": learnerRole ? "Camille Perret" : "Julien Rey", "locale": "fr-CH", "memberships": [membership]]
        let school: [String: Any] = ["id": schoolID.uuidString, "schoolId": schoolID.uuidString,
            "version": 1, "name": "Auto-école du Val-de-Ruz", "timeZone": "Europe/Zurich", "status": "ACTIVE",
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
            "categoryCode": "B", "procedureText": "Préparation, conduite et bilan de la leçon.",
            "cancellationPolicyText": "Conditions fictives destinées au contrôle de la mise en page.",
            "sourceUrls": [], "approved": true, "approvedAt": time]
        let member: [String: Any] = ["id": membershipID.uuidString, "schoolId": schoolID.uuidString, "version": 1,
            "personId": personID.uuidString, "displayName": "Julien Rey", "status": "ACTIVE",
            "roles": roles, "grants": [], "accessEpoch": 1]
        let lesson: [String: Any] = ["id": lessonID.uuidString, "schoolId": schoolID.uuidString, "version": 1,
            "trainingId": trainingID.uuidString, "learnerId": learnerID.uuidString,
            "instructorMembershipId": membershipID.uuidString, "plannedStart": "2026-09-21T07:00:00Z",
            "plannedEnd": "2026-09-21T07:50:00Z", "timeZone": "Europe/Zurich", "meetingPoint": "Gare de Cernier",
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
        // AP175 and its exact published policy: entirely synthetic, with the same read-only transport.
        let profilePolicyID = identifier(200), profileNoticeID = identifier(201)
        let profileFields: [[String: Any]] = SchoolProfileField.allCases.map { field in
            ["field": field.rawValue, "requirement": field.isName ? "REQUIRED" : "OPTIONAL",
             "stage": field.isName ? "JOIN" : "OPTIONAL", "purposeCode": field.purposes[0].rawValue,
             "explanation": "Champ fictif du contrôle de rendu."]
        }
        objects["\(root)/profile-field-policies"] = page([["id": profilePolicyID.uuidString,
            "schoolId": schoolID.uuidString, "version": 1, "status": "PUBLISHED", "effectiveFrom": "2020-01-01T00:00:00Z",
            "fields": profileFields, "noticeVersionId": profileNoticeID.uuidString,
            "approvedByMembershipId": membershipID.uuidString]])
        objects["\(root)/learners/\(learnerID.uuidString)/administrative-profile"] = [
            "id": identifier(202).uuidString, "schoolId": schoolID.uuidString, "version": 1, "learnerId": learnerID.uuidString,
            "firstName": "Camille", "lastName": "Perret", "birthDate": "2005-07-12",
            "postalAddress": ["line1": "Rue des Parcs 12", "line2": null, "postalCode": "2053",
                "locality": "Cernier", "countryCode": "CH"] as [String: Any],
            "contactEmail": "camille@example.invalid", "contactPhone": "+41 00 000 00 00", "profilePhotoDocumentId": null,
            "updatedAt": time, "enteredByMembershipId": membershipID.uuidString, "entrySource": "STAFF_ASSISTED",
            "policyVersionId": profilePolicyID.uuidString]
        objects["\(root)/learners/\(learnerID.uuidString)/action-readiness"] = ["learnerId": learnerID.uuidString,
            "action": "ENTER", "resourceId": null, "ready": true, "blockers": [] as [Any],
            "policyVersionId": profilePolicyID.uuidString, "computedAt": time]
        objects["\(root)/data-policy"] = ["id": identifier(203).uuidString, "schoolId": schoolID.uuidString,
            "version": 1, "status": "APPROVED", "noticeVersionId": profileNoticeID.uuidString,
            "noticeText": "Notice fictive du contrôle de rendu du dossier.",
            "retentionText": "Aucune donnée réelle n’est utilisée dans ce contrôle.", "contactEmail": "contact@example.invalid",
            "approvedAt": time, "approvedByMembershipId": membershipID.uuidString]
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
        // Fiche d’une leçon annulée (clés nouvelles : aucun écran existant n’en dépend).
        objects.merge(cancelledLessonObjects()) { _, new in new }
        // Élève à deux ou trois permis : remplace la formation, l’offre, le référentiel et les leçons du dossier.
        if permitCount > 1 {
            objects.merge(permitObjects(count: permitCount, training: training, offerings: [offering, otherOffering],
                curricula: [curriculum], lessons: [nextLesson, lesson])) { _, new in new }
        }
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
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let window = url.lastPathComponent == "lessons" && query.contains { $0.name == "from" || $0.name == "to" }
        guard var bytes = (window ? responses[url.path + Self.agendaSuffix] : nil) ?? responses[url.path]
        else { throw SchoolAPIError.invalidResponse }
        if window { bytes = try filteredAgenda(bytes, query: query) }
        else if url.lastPathComponent == "lessons", let trainingID = query.first(where: { $0.name == "trainingId" })?.value {
            bytes = try filteredLessons(bytes, trainingID: trainingID)
        }
        return SchoolHTTPResponse(data: bytes, status: 200, url: url, contentType: "application/json")
    }

    /// Comme l’école, la lecture par formation ne renvoie que les leçons de cette formation. Une leçon qui ne
    /// nomme aucune formation reste, et la réponse d’origine est rendue telle quelle quand rien n’est écarté.
    private func filteredLessons(_ bytes: Data, trainingID: String) throws -> Data {
        guard var envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              var page = envelope["data"] as? [String: Any], let lessons = page["items"] as? [[String: Any]]
        else { throw SchoolAPIError.invalidResponse }
        let wanted = trainingID.lowercased()
        let kept = lessons.filter { lesson in
            guard let value = lesson["trainingId"] as? String else { return true }
            return value.lowercased() == wanted
        }
        guard kept.count != lessons.count else { return bytes }
        page["items"] = kept
        envelope["data"] = page
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    private func filteredAgenda(_ bytes: Data, query: [URLQueryItem]) throws -> Data {
        func boundary(_ name: String) throws -> Date? {
            guard let item = query.first(where: { $0.name == name }) else { return nil }
            guard let value = item.value, let date = SchoolLesson.date(value) else { throw SchoolAPIError.invalidResponse }
            return date
        }
        let from = try boundary("from"), to = try boundary("to")
        if let from, let to, to <= from { throw SchoolAPIError.invalidResponse }
        guard var envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              var page = envelope["data"] as? [String: Any], let lessons = page["items"] as? [[String: Any]]
        else { throw SchoolAPIError.invalidResponse }
        page["items"] = try lessons.filter { lesson in
            guard let startValue = lesson["plannedStart"] as? String, let start = SchoolLesson.date(startValue),
                  let endValue = lesson["plannedEnd"] as? String, let end = SchoolLesson.date(endValue)
            else { throw SchoolAPIError.invalidResponse }
            // Same strict overlap as GET /lessons: include crossings, exclude touching bounds.
            return (from.map { end > $0 } ?? true) && (to.map { start < $0 } ?? true)
        }
        envelope["data"] = page
        return try JSONSerialization.data(withJSONObject: envelope)
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
