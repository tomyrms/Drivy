import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolTodayAppointmentsTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return value
    }
    private var now: Date { SchoolLesson.date("2026-10-26T09:30:00Z")! }
    private var instructor: UUID { ConfigurationFixture.membershipID }

    @Test func courseOnlyDayKeepsTheExactOccurrenceAndHidesFinishedSessions() {
        let series = course(occurrences: [occurrence(1, start: "08", end: "09"), occurrence(2, start: "10", end: "11")])
        let result = ordered(courses: [series])
        #expect(result.count == 1)
        guard case .course(let item)? = result.first else { Issue.record("Séance attendue"); return }
        #expect(item.series.id == series.id && item.occurrence.id == identifier(2))
    }

    @Test func ongoingCoursePrecedesFutureLessonAndFutureEventsKeepChronology() throws {
        let lesson = try lesson(1, start: "2026-10-26T10:00:00Z", end: "2026-10-26T11:00:00Z")
        let series = course(occurrences: [occurrence(1, start: "09", end: "10"), occurrence(2, start: "12", end: "13")])
        let result = ordered(lessons: [lesson], courses: [series])
        #expect(result.map(\.id) == ["course:\(series.id):\(identifier(1))", "lesson:\(lesson.id)", "course:\(series.id):\(identifier(2))"])
    }

    @Test func startedLessonAndPreviousUnfinishedLessonStayBeforeAnOngoingCourse() throws {
        let active = try lesson(1, start: "2026-10-26T09:00:00Z", end: "2026-10-26T10:00:00Z", started: true)
        let old = try lesson(2, start: "2026-10-25T09:00:00Z", end: "2026-10-25T10:00:00Z", started: true)
        let series = course(occurrences: [occurrence(1, start: "09", end: "10")])
        let normal = ordered(lessons: [active], unfinished: [old], courses: [series])
        #expect(normal.prefix(2).map(\.id) == ["lesson:\(active.id)", "lesson:\(old.id)"])
        let capturing = ordered(lessons: [active], unfinished: [old], courses: [series], capture: old.id)
        #expect(capturing.first?.id == "lesson:\(old.id)")
    }

    @Test func publicationIsNeverAnUnassignedOrLearnerEngagement() {
        let own = course(occurrences: [occurrence(1, start: "10", end: "11")])
        let other = course(occurrences: [occurrence(2, start: "10", end: "11", instructor: identifier(900))])
        #expect(ordered(courses: [other]).isEmpty)
        #expect(ordered(courses: [course(status: .draft), course(status: .cancelled)]).isEmpty)
        #expect(SchoolTodayAppointments.ordered(lessons: [], unfinished: [], courses: [own], on: now,
            calendar: calendar, instructorID: nil, captureLessonID: nil, now: now).isEmpty)
    }

    @Test func schoolDayUsesItsTimeZoneRatherThanUTC() {
        let localMidnight = SchoolLesson.date("2026-10-25T23:15:00Z")!
        let session = SchoolCourseOccurrence(id: identifier(8), position: 1,
            startsAt: "2026-10-25T23:30:00Z", endsAt: "2026-10-26T00:30:00Z", timeZone: "Europe/Zurich",
            instructorMembershipId: instructor, instructorDisplayName: "Moniteur exemple", attendanceRequired: true)
        let result = SchoolTodayAppointments.ordered(lessons: [], unfinished: [], courses: [course(occurrences: [session])],
            on: now, calendar: calendar, instructorID: instructor, captureLessonID: nil, now: localMidnight)
        #expect(result.count == 1 && result.first?.start == session.start)
    }

    private func ordered(lessons: [SchoolLesson] = [], unfinished: [SchoolLesson] = [], courses: [SchoolCourseSeries] = [],
        capture: UUID? = nil) -> [SchoolAgendaEvent] {
        SchoolTodayAppointments.ordered(lessons: lessons, unfinished: unfinished, courses: courses, on: now,
            calendar: calendar, instructorID: instructor, captureLessonID: capture, now: now)
    }
    private func identifier(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "11111111-1111-4111-8111-%012d", number))!
    }
    private func lesson(_ id: Int, start: String, end: String, started: Bool = false) throws -> SchoolLesson {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson(actualStart: started ? start : nil))) as! [String: Any]
        object["id"] = identifier(id).uuidString; object["plannedStart"] = start; object["plannedEnd"] = end
        return try JSONDecoder().decode(SchoolLesson.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func occurrence(_ id: Int, start: String, end: String, instructor: UUID? = nil) -> SchoolCourseOccurrence {
        SchoolCourseOccurrence(id: identifier(id), position: id, startsAt: "2026-10-26T\(start):00:00Z",
            endsAt: "2026-10-26T\(end):00:00Z", timeZone: "Europe/Zurich", instructorMembershipId: instructor ?? self.instructor,
            instructorDisplayName: "Moniteur exemple", attendanceRequired: true)
    }
    private func course(status: SchoolCourseSeries.Status = .published, occurrences: [SchoolCourseOccurrence]? = nil) -> SchoolCourseSeries {
        let sessions = occurrences ?? [occurrence(1, start: "10", end: "11")]
        return SchoolCourseSeries(id: identifier(100), schoolId: HubFixture.schoolID, version: 1, status: status,
            typeId: identifier(200), typeTitle: "Sensibilisation", title: "Cours exemple", description: "", location: "Salle",
            conditions: "", teachingLanguage: nil, responsibleMembershipId: instructor, responsibleDisplayName: "Moniteur exemple",
            capacity: 10, seatsTaken: 0, remainingSeats: 10, minParticipants: nil, policyVersion: 1, selfCancelHours: 24,
            selfCancellationDeadline: sessions[0].startsAt, firstStartsAt: sessions[0].startsAt, lastEndsAt: sessions.last!.endsAt,
            totalMinutes: 60, publishedAt: status == .draft ? nil : "2026-10-01T08:00:00Z", occurrences: sessions, canManage: true)
    }
}
