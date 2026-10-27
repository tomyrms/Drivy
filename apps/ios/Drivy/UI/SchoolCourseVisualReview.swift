#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Vraies vues et données fictives ; toutes les mutations échouent sans toucher de serveur.
struct SchoolCourseVisualReview: View {
    static let screens: Set<String> = ["course-learner", "course-enrolled", "course-list", "course-editor", "course-roster", "course-attendance", "course-payments-before-start"]
    let screen: String
    @State private var fixture: SchoolCourseVisualFixture?
    @State private var error: String?

    var body: some View {
        Group {
            if let fixture {
                switch screen {
                case "course-editor": SchoolCourseEditorView(model: fixture.editor)
                case "course-roster":
                    NavigationStack { Form { SchoolCourseRosterSection(model: fixture.roster) }.navigationTitle("Participants") }
                case "course-list": SchoolLearnerCoursesView(model: fixture.courses)
                case "course-attendance", "course-payments-before-start": SchoolCourseAttendanceView(model: fixture.attendance)
                default: SchoolCourseLearnerView(model: fixture.learner)
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
    let learner: SchoolCourseLearnerWorkspace
    let courses: SchoolLearnerCoursesWorkspace
    let editor: SchoolCourseEditorWorkspace
    let roster: SchoolCourseRosterWorkspace
    let attendance: SchoolCourseAttendanceWorkspace

    init(screen: String) throws {
        let school = SchoolVisualData.identifier(700), seriesID = SchoolVisualData.identifier(701)
        let member = SchoolVisualData.identifier(702), type = SchoolVisualData.identifier(703)
        let learnerID = SchoolVisualData.identifier(704), enrollmentID = SchoolVisualData.identifier(705)
        let now = Date(), iso = ISO8601DateFormatter()
        let begun = screen == "course-list" || screen == "course-attendance"
        let enrolled = screen == "course-list" || screen == "course-enrolled"
        let first = now.addingTimeInterval(begun ? -86_400 : 7 * 86_400)
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
            publishedAt: screen == "course-editor" ? nil : iso.string(from: now.addingTimeInterval(-14 * 86_400)), occurrences: occurrences, canManage: true)
        let catalogue = SchoolCourseCatalogue(schoolId: school, canManage: true,
            types: [SchoolCourseType(id: type, schoolId: school, stableKey: nil, title: "Sensibilisation", description: "", version: 1, predefined: false)],
            policy: SchoolCoursePolicy(version: 1, selfCancelHours: 24, offerResponseMinutes: 720),
            instructors: [SchoolCourseInstructor(membershipId: member, displayName: "Camille Exemple")])
        let enrollment = SchoolCourseEnrollment(id: enrollmentID, seriesId: seriesID, learnerId: learnerID, version: 1, status: .active,
            source: "SELF", policyVersion: 1, selfCancelHours: 24, selfCancelDeadline: series.selfCancellationDeadline, canSelfCancel: !begun,
            createdAt: iso.string(from: now.addingTimeInterval(-15 * 86_400)), cancelledAt: nil, cancelKind: nil, cancelReason: nil)
        let me = SchoolCourseLearnerState(learnerId: learnerID, state: enrolled ? .enrolled : .available, enrollment: enrolled ? enrollment : nil,
            offer: nil, waitlistPosition: nil, waitlistEnabled: true, contactEmail: "ecole@example.invalid")
        let rows = ["Alex Exemple", "Noa Exemple", "Robin Exemple"].enumerated().map { index, name in
            SchoolCourseSheetRow(enrollmentId: SchoolVisualData.identifier(730 + index), learnerId: SchoolVisualData.identifier(740 + index),
                learnerDisplayName: name, status: .active, cancelledAt: nil,
                attendance: occurrences.map { SchoolCourseAttendanceMark(occurrenceId: $0.id, status: nil, version: nil, recordedAt: nil) },
                requirements: SchoolCourseRequirements(required: 4, present: 0, missing: 4), payments: [], completion: nil)
        }
        let sheet = SchoolCourseSheet(series: series, rights: SchoolCourseSheetRights(canTakeAttendance: true, canRecordPayment: true, canValidate: true), rows: rows)
        var responses: [String: Data] = [:]
        func encoded<T: Encodable>(_ value: T) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["data": JSONSerialization.jsonObject(with: JSONEncoder().encode(value)),
                "requestId": "course-visual", "serverTime": iso.string(from: now)])
        }
        responses["course-catalogue"] = try encoded(catalogue)
        responses["course-series"] = try encoded(SchoolCourseVisualPage(items: begun ? [] : [series]))
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
        let client = SchoolCourseClient(baseURL: URL(string: "https://visual.drivy.invalid")!, tokenSource: SchoolCourseVisualToken(),
            transport: SchoolCourseVisualTransport(responses: responses))
        learner = SchoolCourseLearnerWorkspace(schoolID: school, seriesID: seriesID, timeZone: "Europe/Zurich", client: client)
        courses = SchoolLearnerCoursesWorkspace(schoolID: school, timeZone: "Europe/Zurich", client: client)
        editor = SchoolCourseEditorWorkspace(schoolID: school, membershipID: member, timeZone: "Europe/Zurich", client: client, catalogue: catalogue, series: series)
        let candidates = (1...32).map { index in
            SchoolLearner(id: SchoolVisualData.identifier(800 + index), schoolId: school, personId: SchoolVisualData.identifier(900 + index), version: 1,
                displayName: index >= 31 ? "Zoé Exemple" : String(format: "Élève Exemple %02d", index), contactEmail: nil, contactPhone: nil,
                archivedAt: nil, profileReadiness: "READY", profilePhotoDocumentId: nil)
        }
        roster = SchoolCourseRosterWorkspace(schoolID: school, seriesID: seriesID, client: client, learners: candidates)
        attendance = SchoolCourseAttendanceWorkspace(schoolID: school, seriesID: seriesID, timeZone: "Europe/Zurich", client: client)
    }
}

private struct SchoolCourseVisualPage: Encodable { let items: [SchoolCourseSeries] }
@MainActor private final class SchoolCourseVisualToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-course-visual-token" }
}
private struct SchoolCourseVisualTransport: SchoolHTTPTransport {
    let responses: [String: Data]
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "visual.drivy.invalid" else { throw SchoolAPIError.invalidResponse }
        guard (request.httpMethod ?? "GET") == "GET" else { throw URLError(.notConnectedToInternet) }
        let route = url.pathComponents.dropFirst(4).joined(separator: "/")
        guard let data = responses[route] else { throw SchoolAPIError.invalidResponse }
        return SchoolHTTPResponse(data: data, status: 200, url: url, contentType: "application/json")
    }
}
#endif
