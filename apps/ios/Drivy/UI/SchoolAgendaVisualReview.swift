#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Agenda réel, données fictives et pannes déterministes. Aucun réseau ni écriture métier.
@MainActor enum SchoolAgendaVisualData {
    static let screens: Set<String> = ["agenda-mixed", "agenda-mixed-month", "agenda-courses-error", "agenda-courses-stale"]

    static func transport(overriding original: [String: Data], scenario: String) throws -> SchoolAgendaVisualTransport {
        var responses = original
        let root = "/v1/schools/\(SchoolVisualData.schoolID.uuidString)"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let today = calendar.startOfDay(for: Date())
        let iso = ISO8601DateFormatter()
        func time(_ day: Int, _ hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0,
                of: calendar.date(byAdding: .day, value: day, to: today)!)!
        }
        func envelope(_ object: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["data": object, "requestId": "10000000-0000-4000-8000-000000000399", "serverTime": iso.string(from: today)])
        }
        func data(_ path: String) throws -> [String: Any] {
            guard let bytes = responses[path],
                  let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let result = value["data"] as? [String: Any] else { throw SchoolAPIError.invalidResponse }
            return result
        }
        var school = try data(root)
        var modules = school["modules"] as? [String: Any] ?? [:]
        modules["collectiveCoursesEnabled"] = true
        school["modules"] = modules
        responses[root] = try envelope(school)

        var lesson = try data("\(root)/lessons/\(SchoolVisualData.lessonID.uuidString)")
        lesson["plannedStart"] = iso.string(from: time(0, 11))
        lesson["plannedEnd"] = iso.string(from: time(0, 12))
        lesson["actualStart"] = NSNull(); lesson["actualEnd"] = NSNull()
        lesson["status"] = "PLANNED"
        lesson["publicationVersion"] = 0; lesson["currentPublishedRevisionId"] = NSNull()
        responses["\(root)/lessons" + SchoolVisualTransport.agendaSuffix] = try envelope(["items": [lesson], "nextCursor": NSNull()])
        responses["\(root)/lessons/\(SchoolVisualData.lessonID.uuidString)"] = try envelope(lesson)

        let typeID = SchoolVisualData.identifier(300)
        let occurrences = [(0, 9), (0, 14), (1, 9)].enumerated().map { index, entry in
            SchoolCourseOccurrence(id: SchoolVisualData.identifier(301 + index), position: index + 1,
                startsAt: iso.string(from: time(entry.0, entry.1)), endsAt: iso.string(from: time(entry.0, entry.1 + 1)),
                timeZone: "Europe/Zurich", instructorMembershipId: SchoolVisualData.membershipID,
                instructorDisplayName: "Julien Rey", attendanceRequired: true)
        }
        let series = SchoolCourseSeries(id: SchoolVisualData.identifier(310), schoolId: SchoolVisualData.schoolID,
            version: 1, status: .published, typeId: typeID, typeTitle: "Sensibilisation", title: "Sensibilisation",
            description: "", location: "Salle de Cernier", conditions: "", teachingLanguage: "fr",
            responsibleMembershipId: SchoolVisualData.membershipID, responsibleDisplayName: "Julien Rey",
            capacity: 12, seatsTaken: 3, remainingSeats: 9, minParticipants: nil,
            policyVersion: 1, selfCancelHours: 24, selfCancellationDeadline: iso.string(from: time(-1, 9)),
            firstStartsAt: occurrences[0].startsAt, lastEndsAt: occurrences[2].endsAt, totalMinutes: 180,
            publishedAt: iso.string(from: time(-2, 9)), occurrences: occurrences, canManage: true)
        let catalogue = SchoolCourseCatalogue(schoolId: SchoolVisualData.schoolID, canManage: true,
            types: [SchoolCourseType(id: typeID, schoolId: SchoolVisualData.schoolID, stableKey: "visual-sensibilisation",
                title: "Sensibilisation", description: "", version: 1, predefined: false)],
            policy: SchoolCoursePolicy(version: 1, selfCancelHours: 24, offerResponseMinutes: 720),
            instructors: [SchoolCourseInstructor(membershipId: SchoolVisualData.membershipID, displayName: "Julien Rey")])
        responses["\(root)/course-catalogue"] = try envelope(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalogue)))
        responses["\(root)/course-series/\(series.id.uuidString)"] = try envelope(JSONSerialization.jsonObject(with: JSONEncoder().encode(series)))
        let failure = scenario == "agenda-courses-error" ? 1 : scenario == "agenda-courses-stale" ? 2 : nil
        return SchoolAgendaVisualTransport(base: SchoolVisualTransport(responses: responses), series: [series], failureAt: failure)
    }
}

actor SchoolAgendaVisualTransport: SchoolHTTPTransport {
    private let base: SchoolVisualTransport
    private let series: [SchoolCourseSeries]
    private let failureAt: Int?
    private var courseReads = 0

    init(base: SchoolVisualTransport, series: [SchoolCourseSeries], failureAt: Int?) {
        self.base = base; self.series = series; self.failureAt = failureAt
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "visual.drivy.invalid", (request.httpMethod ?? "GET") == "GET"
        else { throw SchoolAPIError.invalidResponse }
        guard url.lastPathComponent == "course-series" else { return try await base.send(request) }
        courseReads += 1
        if courseReads == failureAt { throw URLError(.notConnectedToInternet) }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let from = query.first(where: { $0.name == "from" })?.value.flatMap(SchoolLesson.date),
              let to = query.first(where: { $0.name == "to" })?.value.flatMap(SchoolLesson.date), from < to
        else { throw SchoolAPIError.invalidResponse }
        let matching = series.filter { series in
            series.occurrences.contains { occurrence in
                guard let start = occurrence.start, let end = occurrence.end else { return false }
                return end > from && start < to
            }
        }
        struct Page: Encodable { let items: [SchoolCourseSeries] }
        struct Envelope: Encodable { let data: Page; let requestId = "10000000-0000-4000-8000-000000000399"; let serverTime = "2026-10-26T10:00:00Z" }
        return SchoolHTTPResponse(data: try JSONEncoder().encode(Envelope(data: Page(items: matching))),
            status: 200, url: url, contentType: "application/json")
    }
}
#endif
