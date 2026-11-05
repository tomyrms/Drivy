#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Vraies vues et clients ; transport synthétique, sans réseau ni persistance utilisateur.
/// Les scènes historiques gardent leurs mutations en échec ; les parcours #37 ont un script explicite.
struct SchoolCourseVisualReview: View {
    static let screens: Set<String> = ["course-learner", "course-enrolled", "course-list", "course-editor", "course-roster", "course-attendance", "course-payments-before-start",
        "course-payments-history", "course-list-empty", "course-list-error", "course-list-loading", "course-learner-error", "course-learner-loading",
        "course-offered", "course-offer-expired", "course-cancel-success", "course-after-deadline", "course-facts", "course-attendance-only"]
    let screen: String
    @State private var fixture: SchoolCourseVisualFixture?
    @State private var error: String?

    var body: some View {
        Group {
            if let fixture {
                Group { switch screen {
                case "course-editor": SchoolCourseEditorView(model: fixture.editor)
                case "course-roster":
                    NavigationStack { Form { SchoolCourseRosterSection(model: fixture.roster) }.navigationTitle("Participants") }
                case "course-list", "course-list-empty", "course-list-error", "course-list-loading": SchoolLearnerCoursesView(model: fixture.courses)
                case "course-attendance", "course-payments-before-start", "course-payments-history", "course-facts", "course-attendance-only": SchoolCourseAttendanceView(model: fixture.attendance)
                default: SchoolCourseLearnerView(model: fixture.learner)
                } }
                .environment(\.schoolMessagingEntry, fixture.messagingEntry)
                .environment(\.openURL, OpenURLAction { url in
                    guard screen == "course-after-deadline" else { return .systemAction }
                    fixture.probe.mailOpened = url == SchoolCourseEnrollmentFormat.mailURL("ecole@example.invalid", courseTitle: "Sensibilisation du soir")
                    return .handled
                })
                .safeAreaInset(edge: .bottom) {
                    if fixture.isJourney {
                        Text(fixture.probe.summary).font(.caption2).monospacedDigit()
                            .accessibilityIdentifier("course-fixture-witness")
                    }
                }
            } else if let error { Text(error) }
            else { ProgressView("Préparation…") }
        }
        .task {
            guard fixture == nil else { return }
            do { fixture = try SchoolCourseVisualFixture(screen: screen) }
            catch { self.error = "Préparation impossible" }
        }
    }
}

@MainActor private struct SchoolCourseVisualFixture {
    let probe: SchoolCourseVisualProbe
    let isJourney: Bool
    let messagingEntry: SchoolMessagingEntry?
    let learner: SchoolCourseLearnerWorkspace
    let courses: SchoolLearnerCoursesWorkspace
    let editor: SchoolCourseEditorWorkspace
    let roster: SchoolCourseRosterWorkspace
    let attendance: SchoolCourseAttendanceWorkspace

    init(screen: String) throws {
        let isJourney = ["course-offered", "course-offer-expired", "course-cancel-success", "course-after-deadline", "course-facts", "course-attendance-only"].contains(screen)
        self.isJourney = isJourney
        let probe = SchoolCourseVisualProbe()
        self.probe = probe
        messagingEntry = screen == "course-after-deadline" ? SchoolMessagingEntry(scopeID: "synthetic-course-contact", makeView: { _ in
            AnyView(SchoolCourseVisualContact().onAppear { probe.messagesOpened = true })
        }) : nil
        let school = SchoolVisualData.identifier(700), seriesID = SchoolVisualData.identifier(701)
        let member = SchoolVisualData.identifier(702), type = SchoolVisualData.identifier(703)
        let learnerID = SchoolVisualData.identifier(704), enrollmentID = SchoolVisualData.identifier(705)
        let now = Date(), iso = ISO8601DateFormatter()
        let facts = screen == "course-facts"
        let late = screen == "course-after-deadline"
        let offered = screen == "course-offered" || screen == "course-offer-expired"
        let begun = screen == "course-list" || screen == "course-attendance" || facts || screen == "course-attendance-only"
        let enrolled = screen == "course-list" || screen == "course-enrolled" || screen == "course-cancel-success" || late
        let first = now.addingTimeInterval(facts ? -22 * 86_400 : late ? 43_200 : begun ? -86_400 : 7 * 86_400)
        let occurrences = (0..<4).map { index in
            SchoolCourseOccurrence(id: SchoolVisualData.identifier(710 + index), position: index + 1,
                startsAt: iso.string(from: first.addingTimeInterval(Double(index) * 7 * 86_400)),
                endsAt: iso.string(from: first.addingTimeInterval(Double(index) * 7 * 86_400 + 7_200)),
                timeZone: "Europe/Zurich", instructorMembershipId: member, instructorDisplayName: "Camille Exemple", attendanceRequired: true)
        }
        let series = SchoolCourseSeries(id: seriesID, schoolId: school, version: 1, status: screen == "course-editor" ? .draft : .published,
            typeId: type, typeTitle: "Sensibilisation", title: "Sensibilisation du soir",
            description: "Anticiper les dangers et partager la route. Exercices en groupe et échanges autour de situations concrètes.",
            location: "Salle des Tilleuls", conditions: "Apporte ton permis d’élève. Le règlement se fait sur place à la première séance.", teachingLanguage: "fr",
            responsibleMembershipId: member, responsibleDisplayName: "Camille Exemple", capacity: 12, seatsTaken: 3, remainingSeats: 9,
            minParticipants: 4, policyVersion: 1, selfCancelHours: 24, selfCancellationDeadline: iso.string(from: first.addingTimeInterval(-86_400)),
            firstStartsAt: occurrences[0].startsAt, lastEndsAt: occurrences[3].endsAt, totalMinutes: 480,
            publishedAt: screen == "course-editor" ? nil : iso.string(from: now.addingTimeInterval(-14 * 86_400)), occurrences: occurrences,
            canManage: !isJourney || facts || screen == "course-attendance-only")
        let catalogue = SchoolCourseCatalogue(schoolId: school, canManage: true,
            types: [SchoolCourseType(id: type, schoolId: school, stableKey: nil, title: "Sensibilisation", description: "", version: 1, predefined: false)],
            policy: SchoolCoursePolicy(version: 1, selfCancelHours: 24, offerResponseMinutes: 720),
            instructors: [SchoolCourseInstructor(membershipId: member, displayName: "Camille Exemple")])
        let enrollment = SchoolCourseEnrollment(id: enrollmentID, seriesId: seriesID, learnerId: learnerID, version: 1, status: .active,
            source: "SELF", policyVersion: 1, selfCancelHours: 24, selfCancelDeadline: series.selfCancellationDeadline, canSelfCancel: !begun && !late,
            createdAt: iso.string(from: now.addingTimeInterval(-15 * 86_400)), cancelledAt: nil, cancelKind: nil, cancelReason: nil)
        let offer = SchoolCourseOffer(id: SchoolVisualData.identifier(706), seriesId: seriesID,
            expiresAt: iso.string(from: now.addingTimeInterval(screen == "course-offer-expired" ? -60 : 3600)), status: "ACTIVE")
        let me = SchoolCourseLearnerState(learnerId: learnerID, state: offered ? .offered : enrolled ? .enrolled : .available, enrollment: enrolled ? enrollment : nil,
            offer: offered ? offer : nil, waitlistPosition: nil, waitlistEnabled: true, contactEmail: "ecole@example.invalid")
        let history = [
            SchoolCoursePayment(id: SchoolVisualData.identifier(750), amountCents: 3000, recordedAt: "2026-09-21T10:00:00Z", note: nil, voidedAt: nil, voidReason: nil),
            SchoolCoursePayment(id: SchoolVisualData.identifier(751), amountCents: 5000, recordedAt: "2026-09-22T10:00:00Z", note: nil, voidedAt: "2026-09-23T10:00:00Z", voidReason: "Saisie corrigée dans l’exemple."),
            SchoolCoursePayment(id: SchoolVisualData.identifier(752), amountCents: 2000, recordedAt: "2026-09-23T11:00:00Z", note: nil, voidedAt: nil, voidReason: nil)
        ]
        let names = facts || screen == "course-attendance-only" ? ["Alex Exemple"] : ["Alex Exemple", "Noa Exemple", "Robin Exemple"]
        let rows = names.enumerated().map { index, name in
            SchoolCourseSheetRow(enrollmentId: SchoolVisualData.identifier(730 + index), learnerId: SchoolVisualData.identifier(740 + index),
                learnerDisplayName: name, status: .active, cancelledAt: nil,
                attendance: occurrences.map { SchoolCourseAttendanceMark(occurrenceId: $0.id, status: facts && $0.position < 4 ? .present : nil,
                    version: facts && $0.position < 4 ? 1 : nil, recordedAt: facts && $0.position < 4 ? $0.endsAt : nil) },
                requirements: SchoolCourseRequirements(required: 4, present: facts ? 3 : 0, missing: facts ? 1 : 4),
                payments: screen == "course-payments-history" && index == 0 ? history : [], completion: nil)
        }
        let sheet = SchoolCourseSheet(series: series, rights: SchoolCourseSheetRights(canTakeAttendance: screen != "course-payments-history",
            canRecordPayment: screen != "course-attendance-only", canValidate: screen != "course-payments-history" && screen != "course-attendance-only"), rows: rows)
        var responses: [String: Data] = [:]
        func encoded<T: Encodable>(_ value: T) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["data": JSONSerialization.jsonObject(with: JSONEncoder().encode(value)),
                "requestId": "course-visual", "serverTime": iso.string(from: now)])
        }
        responses["course-catalogue"] = try encoded(catalogue)
        responses["course-series"] = try encoded(SchoolCourseVisualPage(items: begun || screen == "course-list-empty" ? [] : [series]))
        responses["course-series/\(seriesID)/me"] = try encoded(SchoolCourseLearnerReply(series: series, me: me))
        responses["course-series/\(seriesID)"] = try encoded(series)
        responses["course-series/\(seriesID)/sheet"] = try encoded(sheet)
        responses["course-enrollments/me"] = try encoded(SchoolCourseMine(items: enrolled ? [enrollment] : [], offers: []))
        responses["course-follows/me"] = try encoded(SchoolCourseFollows(typeIds: []))
        responses["course-progress/me"] = try encoded(SchoolCourseProgress(completions: [], enrollments: enrolled ? [
            SchoolCourseProgress.Enrollment(enrollmentId: enrollmentID, seriesId: seriesID,
                requirements: SchoolCourseRequirements(required: 4, present: 1, missing: 3), attendance: [])] : []))
        responses["course-series/\(seriesID)/enrollments"] = try JSONSerialization.data(withJSONObject: ["data": ["items": [], "waitlist": []],
            "requestId": "course-visual", "serverTime": iso.string(from: now)])
        var steps: [SchoolCourseVisualStep] = []
        if screen == "course-offered" || screen == "course-cancel-success" {
            let cancelling = screen == "course-cancel-success"
            let resultEnrollment = SchoolCourseEnrollment(id: enrollmentID, seriesId: seriesID, learnerId: learnerID,
                version: cancelling ? 2 : 1, status: cancelling ? .cancelled : .active, source: cancelling ? "SELF" : "OFFER",
                policyVersion: 1, selfCancelHours: 24, selfCancelDeadline: series.selfCancellationDeadline, canSelfCancel: !cancelling,
                createdAt: enrollment.createdAt, cancelledAt: cancelling ? iso.string(from: now) : nil, cancelKind: cancelling ? "SELF" : nil, cancelReason: nil)
            // Une réponse de frontière, pas une imitation du moteur de réservation.
            var seriesJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(series)) as! [String: Any]
            seriesJSON["seatsTaken"] = cancelling ? 2 : 4; seriesJSON["remainingSeats"] = cancelling ? 10 : 8
            let resultSeries = try JSONDecoder().decode(SchoolCourseSeries.self, from: JSONSerialization.data(withJSONObject: seriesJSON))
            let result = SchoolCourseLearnerReply(series: resultSeries, me: SchoolCourseLearnerState(learnerId: learnerID,
                state: cancelling ? .cancelled : .enrolled, enrollment: resultEnrollment, offer: nil,
                waitlistPosition: nil, waitlistEnabled: true, contactEmail: "ecole@example.invalid"))
            steps.append(SchoolCourseVisualStep(method: "POST", route: cancelling ? "course-enrollments/\(enrollmentID)/cancel" : "course-offers/\(offer.id)/accept",
                status: cancelling ? 200 : 201, data: try encoded(result), readRoute: "course-series/\(seriesID)/me",
                event: cancelling ? "cancel" : "accept", bodyField: nil, bodyValue: nil))
        }
        if facts {
            let row = rows[0], date = iso.string(from: now)
            let paid = [SchoolCoursePayment(id: SchoolVisualData.identifier(760), amountCents: 8000, recordedAt: date, note: nil, voidedAt: nil, voidReason: nil)]
            for phase in 0..<3 {
                let present = phase > 0, completed = phase > 1
                let result = SchoolCourseSheet(series: series, rights: sheet.rights, rows: [SchoolCourseSheetRow(enrollmentId: row.enrollmentId,
                    learnerId: row.learnerId, learnerDisplayName: row.learnerDisplayName, status: .active, cancelledAt: nil,
                    attendance: present ? occurrences.map { SchoolCourseAttendanceMark(occurrenceId: $0.id, status: .present, version: 1, recordedAt: date) } : row.attendance,
                    requirements: SchoolCourseRequirements(required: 4, present: present ? 4 : 3, missing: present ? 0 : 1), payments: paid,
                    completion: completed ? SchoolCourseCompletion(id: SchoolVisualData.identifier(761), validatedAt: date, seriesId: seriesID, revokedAt: nil) : nil)])
                let suffix = phase == 0 ? "payments" : phase == 1 ? "attendance/\(occurrences[3].id)" : "validate"
                steps.append(SchoolCourseVisualStep(method: phase == 1 ? "PUT" : "POST", route: "course-enrollments/\(row.enrollmentId)/\(suffix)",
                    status: phase == 1 ? 200 : 201, data: try encoded(result), readRoute: "course-series/\(seriesID)/sheet",
                    event: phase == 0 ? "payment" : phase == 1 ? "attendance" : "validation",
                    bodyField: phase == 0 ? "amountCents" : phase == 1 ? "status" : nil, bodyValue: phase == 0 ? "8000" : phase == 1 ? "PRESENT" : nil))
            }
        }
        let client = SchoolCourseClient(baseURL: URL(string: "https://visual.drivy.invalid")!, tokenSource: SchoolCourseVisualToken(),
            transport: SchoolCourseVisualTransport(responses: responses, screen: screen, steps: steps, probe: probe))
        learner = SchoolCourseLearnerWorkspace(schoolID: school, seriesID: seriesID, timeZone: "Europe/Zurich", client: client)
        courses = SchoolLearnerCoursesWorkspace(schoolID: school, timeZone: "Europe/Zurich", client: client)
        editor = SchoolCourseEditorWorkspace(schoolID: school, membershipID: member, timeZone: "Europe/Zurich", client: client, catalogue: catalogue, series: series)
        let candidates = (1...32).map { index in
            SchoolLearner(id: SchoolVisualData.identifier(800 + index), schoolId: school, personId: SchoolVisualData.identifier(900 + index), version: 1,
                displayName: index >= 31 ? "Zoé Exemple" : String(format: "Élève Exemple %02d", index), contactEmail: nil, contactPhone: nil,
                archivedAt: nil, profileReadiness: "READY", profilePhotoDocumentId: nil)
        }
        // L’app ne connaît d’abord qu’une page : les deux Zoé, après le trentième nom, n’arrivent qu’avec la lecture de l’annuaire (A30).
        let pageSize = 12
        roster = SchoolCourseRosterWorkspace(schoolID: school, seriesID: seriesID, client: client, learners: Array(candidates.prefix(pageSize)),
            learnerPages: { cursor in
                let start = cursor.flatMap { Int($0) } ?? 0
                let end = min(candidates.count, start + pageSize)
                return SchoolPage(items: Array(candidates[start..<end]), nextCursor: end < candidates.count ? String(end) : nil)
            })
        attendance = SchoolCourseAttendanceWorkspace(schoolID: school, seriesID: seriesID, timeZone: "Europe/Zurich", client: client)
    }
}

private struct SchoolCourseVisualPage: Encodable { let items: [SchoolCourseSeries] }
@MainActor private final class SchoolCourseVisualToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-course-visual-token" }
}
/// Témoins de frontière uniquement : aucune preuve d'écriture serveur ou d'envoi d'un message.
@MainActor @Observable private final class SchoolCourseVisualProbe {
    var events: [String] = []
    var unexpected = 0
    var mailOpened = false
    var messagesOpened = false
    var summary: String { "mutations=\(events.count); events=\(events.joined(separator: ",")); unexpected=\(unexpected); mail=\(mailOpened ? 1 : 0); messages=\(messagesOpened ? 1 : 0)" }
}

private struct SchoolCourseVisualContact: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Text("Messagerie synthétique, aucun envoi")
                .accessibilityIdentifier("course-fixture-messages")
                .navigationTitle("Messages")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

private struct SchoolCourseVisualStep: Sendable {
    let method: String, route: String
    let status: Int
    let data: Data
    let readRoute: String, event: String
    let bodyField: String?, bodyValue: String?
}

private actor SchoolCourseVisualTransport: SchoolHTTPTransport {
    private var responses: [String: Data]
    let screen: String
    private var steps: [SchoolCourseVisualStep]
    private let probe: SchoolCourseVisualProbe

    init(responses: [String: Data], screen: String, steps: [SchoolCourseVisualStep], probe: SchoolCourseVisualProbe) {
        self.responses = responses; self.screen = screen; self.steps = steps; self.probe = probe
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "visual.drivy.invalid" else { throw SchoolAPIError.invalidResponse }
        if screen.hasSuffix("-loading") { try await Task.sleep(for: .seconds(120)) }
        if screen.hasSuffix("-error") { throw URLError(.notConnectedToInternet) }
        let route = url.pathComponents.dropFirst(4).joined(separator: "/")
        if (request.httpMethod ?? "GET") != "GET" {
            guard let step = steps.first, step.method == request.httpMethod, step.route == route,
                  let body = request.httpBody,
                  let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let operation = object["operationId"] as? String, UUID(uuidString: operation) != nil,
                  step.bodyField == nil || object[step.bodyField!].map({ String(describing: $0) }) == step.bodyValue else {
                await MainActor.run { probe.unexpected += 1 }
                throw URLError(.notConnectedToInternet)
            }
            steps.removeFirst()
            responses[step.readRoute] = step.data
            await MainActor.run { probe.events.append(step.event) }
            return SchoolHTTPResponse(data: step.data, status: step.status, url: url, contentType: "application/json")
        }
        guard let data = responses[route] else { throw SchoolAPIError.invalidResponse }
        return SchoolHTTPResponse(data: data, status: 200, url: url, contentType: "application/json")
    }
}
#endif
