import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolAgendaCoursesTests {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Zurich")!
        value.firstWeekday = 2
        return value
    }()
    private var day: Date { SchoolLesson.date("2026-10-26T12:00:00Z")! }
    private var scope: SchoolAgendaScope {
        SchoolAgendaScope(prefix: "person:school:epoch1:all", range: SchoolAgendaMonth.weekRange(for: day, calendar: calendar))
    }

    @Test func failedFirstReadIsDistinctFromAConfirmedEmptyPeriodAndRetrySucceeds() async {
        let model = SchoolAgendaCourses()
        #expect(model.isLoading(in: scope))
        await model.load(scope: scope) { throw URLError(.notConnectedToInternet) }
        #expect(!model.isComplete(in: scope))
        #expect(!model.isLoading(in: scope))
        #expect(model.readAt == nil)
        #expect(model.error(in: scope, timeZone: "Europe/Zurich")?.hasPrefix("Cours non actualisés") == true)
        await model.load(scope: scope) { [] }
        #expect(model.isComplete(in: scope))
        #expect(model.items(in: scope).isEmpty)
        #expect(model.error(in: scope, timeZone: "Europe/Zurich") == nil)
    }

    @Test func failedRefreshRetainsOnlyTheSameScopeAndShowsItsOwnReadDate() async {
        let model = SchoolAgendaCourses(), series = course()
        await model.load(scope: scope) { [series] }
        let readAt = model.readAt
        await model.load(scope: scope) { throw URLError(.timedOut) }
        #expect(model.items(in: scope) == [series])
        #expect(model.readAt == readAt)
        #expect(model.error(in: scope, timeZone: "Europe/Zurich")?.contains("Dernière lecture réussie") == true)
        for other in [SchoolAgendaScope(prefix: "other-person:school:epoch1:all", range: scope.range),
                      SchoolAgendaScope(prefix: "person:school:epoch2:all", range: scope.range),
                      SchoolAgendaScope(prefix: "person:school:epoch1:mine", range: scope.range),
                      SchoolAgendaScope(prefix: scope.prefix, range: SchoolAgendaMonth.weekRange(for: day.addingTimeInterval(7 * 86400), calendar: calendar))] {
            #expect(model.items(in: other).isEmpty)
            #expect(model.error(in: other, timeZone: "Europe/Zurich") == nil)
            await model.load(scope: other) { throw URLError(.timedOut) }
            #expect(model.items(in: other).isEmpty)
            #expect(model.readAt == nil)
        }
    }

    @Test func newerReadWinsEvenWhenTheOlderReadCompletesLastInTheSameScope() async {
        let model = SchoolAgendaCourses(), gate = AgendaCourseReadGate()
        let wanted = scope, old = course(id: 1), fresh = course(id: 2)
        let first = Task { await model.load(scope: wanted) { try await gate.fetch(1) } }
        await gate.waitForStart(1)
        let second = Task { await model.load(scope: wanted) { try await gate.fetch(2) } }
        await gate.waitForStart(2)
        gate.finish(2, with: [fresh]); _ = await second.value
        gate.finish(1, with: [old]); _ = await first.value
        #expect(model.items(in: wanted) == [fresh])
        #expect(model.isComplete(in: wanted))
    }

    @Test func changedContextRejectsLateResponseBeforeTheNextReadStarts() async {
        let model = SchoolAgendaCourses(), gate = AgendaCourseReadGate()
        let wanted = scope
        var isCurrent = true
        let reading = Task { await model.load(scope: wanted, isCurrent: { isCurrent }) { try await gate.fetch(1) } }
        await gate.waitForStart(1)
        isCurrent = false
        gate.finish(1, with: [course()]); _ = await reading.value
        #expect(model.items.isEmpty)
        #expect(model.readAt == nil)
        #expect(model.state == .idle && model.error(in: wanted, timeZone: "Europe/Zurich") == nil)
        model.reset()
        #expect(model.scope == nil)
    }

    @Test func cancelledInitialReadCanRetryWithoutAcceptingItsResponseOrSpinningForever() async {
        let model = SchoolAgendaCourses(), gate = AgendaCourseReadGate(), wanted = scope
        let reading = Task { await model.load(scope: wanted) { try await gate.fetch(1) } }
        await gate.waitForStart(1)
        reading.cancel()
        gate.finish(1, with: [course()]); _ = await reading.value
        #expect(model.items.isEmpty)
        #expect(!model.isComplete(in: wanted))
        #expect(model.state == .interrupted && !model.isLoading(in: wanted))
        #expect(model.error(in: wanted, timeZone: "Europe/Zurich")?.contains("L’actualisation a été interrompue") == true)
        await model.load(scope: wanted) { [] }
        #expect(model.isComplete(in: wanted) && model.error(in: wanted, timeZone: "Europe/Zurich") == nil)
    }

    @Test func cancelledRefreshKeepsItsLastReadAndOffersRetryAfterAFetchFailure() async {
        let model = SchoolAgendaCourses(), gate = AgendaCourseReadGate(), wanted = scope, original = course()
        await model.load(scope: wanted) { [original] }
        let readAt = model.readAt
        let reading = Task {
            await model.load(scope: wanted) {
                _ = try await gate.fetch(1)
                throw URLError(.notConnectedToInternet)
            }
        }
        await gate.waitForStart(1)
        reading.cancel()
        gate.finish(1, with: []); _ = await reading.value
        #expect(model.state == .interrupted && !model.isLoading(in: wanted))
        #expect(model.items(in: wanted) == [original] && model.readAt == readAt)
        #expect(!model.isComplete(in: wanted))
        let message = model.error(in: wanted, timeZone: "Europe/Zurich")
        #expect(message?.contains("L’actualisation a été interrompue") == true)
        #expect(message?.contains("Dernière lecture réussie") == true)
        let fresh = course(id: 2)
        await model.load(scope: wanted) { [fresh] }
        #expect(model.items(in: wanted) == [fresh] && model.isComplete(in: wanted))
    }

    @Test func revokedAccessDiscardsPreviouslyReadCoursesAndRequestsAccountRefresh() async {
        let model = SchoolAgendaCourses()
        await model.load(scope: scope) { [course()] }
        let refresh = await model.load(scope: scope) { throw SchoolPlanningFailure.forbidden }
        #expect(refresh)
        #expect(model.items.isEmpty && model.readAt == nil)
        #expect(!model.isComplete(in: scope))
    }

    @Test func resetDuringAnInflightReadRejectsTheResponse() async {
        let model = SchoolAgendaCourses(), gate = AgendaCourseReadGate(), wanted = scope
        let reading = Task { await model.load(scope: wanted) { try await gate.fetch(1) } }
        await gate.waitForStart(1)
        model.reset()
        gate.finish(1, with: [course()]); _ = await reading.value
        #expect(model.scope == nil && model.items.isEmpty)
        #expect(model.state == .idle)
    }

    @Test func serverListLimitNeverClaimsExhaustiveCountsOrAFreeDay() async {
        let model = SchoolAgendaCourses()
        await model.load(scope: scope) { (1...200).map { course(id: $0) } }
        #expect(model.state == .partial)
        #expect(!model.isComplete(in: scope))
        #expect(model.items.count == 200)
        #expect(SchoolAgendaEvent.summary([], isComplete: model.isComplete(in: scope)).spokenCount == "Agenda incomplet")
    }

    @Test func dailyChronologyMixesCoursesAndLessonsWithStableDistinctIdentities() throws {
        let first = course(id: 1, occurrences: [occurrence(1, hour: 9), occurrence(2, hour: 14)])
        let lesson = try lesson(id: 1, start: "2026-10-26T10:00:00Z", end: "2026-10-26T10:50:00Z")
        let result = SchoolAgendaEvent.day(lessons: [lesson], courses: [first], on: day, calendar: calendar)
        #expect(result.map(\.start) == [SchoolLesson.date("2026-10-26T08:00:00Z"), lesson.startsAt, SchoolLesson.date("2026-10-26T13:00:00Z")])
        #expect(Set(result.map(\.id)).count == 3)
        #expect(SchoolAgendaEvent.summary(result, isComplete: true).spokenCount == "1 leçon, 2 séances collectives")
        let repeated = SchoolAgendaEvent.day(lessons: [lesson, lesson], courses: [first, first], on: day, calendar: calendar)
        #expect(repeated == result)
    }

    @Test func equalStartAndEndTimesHaveAnOrderIndependentOfResponseOrder() throws {
        let a = course(id: 1, occurrences: [occurrence(1, hour: 9)])
        let b = course(id: 2, occurrences: [occurrence(2, hour: 9)])
        let lesson = try lesson(id: 1, start: "2026-10-26T08:00:00Z", end: "2026-10-26T09:00:00Z")
        let ordered = SchoolAgendaEvent.day(lessons: [lesson], courses: [a, b], on: day, calendar: calendar)
        let reversed = SchoolAgendaEvent.day(lessons: [lesson], courses: [b, a], on: day, calendar: calendar)
        #expect(ordered == reversed)
        #expect(ordered.count == 3)
    }

    @Test func summaryCountsEachOccurrenceAndDistinguishesDraftAndCancelledCourses() {
        let draft = course(id: 1, status: .draft, occurrences: [occurrence(1, hour: 9)])
        let cancelled = course(id: 2, status: .cancelled, occurrences: [occurrence(2, hour: 11)])
        let published = course(id: 3, occurrences: [occurrence(3, hour: 14)])
        let events = SchoolAgendaEvent.day(lessons: [], courses: [draft, cancelled, published], on: day, calendar: calendar)
        let summary = SchoolAgendaEvent.summary(events, isComplete: false)
        #expect(summary.total == 3 && summary.lessonCount == 0)
        #expect(summary.marks == [.active, .provisional, .closed])
        #expect(summary.spokenCount == "3 séances collectives, dont 1 brouillon, dont 1 séance annulée, Agenda incomplet")
    }

    @Test func instructorFilterUsesTheOccurrenceInstructorNotOnlyTheSeriesResponsible() {
        let other = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        let series = course(occurrences: [occurrence(1, hour: 9), occurrence(2, hour: 14, instructor: other)])
        let events = SchoolAgendaEvent.day(lessons: [], courses: [series], on: day, calendar: calendar, instructorID: other)
        #expect(events.count == 1)
        #expect(events.first?.start == SchoolLesson.date("2026-10-26T13:00:00Z"))
        #expect(SchoolAgendaEvent.summary(events, isComplete: true).spokenCount == "1 séance collective")
    }

    @Test func coursesUseSchoolMidnightAndPreserveBothRepeatedAutumnHours() {
        let instants = ["2026-10-24T22:30:00Z", "2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z", "2026-10-25T23:30:00Z"]
        let series = course(occurrences: instants.enumerated().map { index, instant in
            occurrence(index + 1, start: instant, end: ISO8601DateFormatter().string(from: SchoolLesson.date(instant)!.addingTimeInterval(1800)))
        })
        let autumn = SchoolLesson.date("2026-10-25T12:00:00Z")!
        let result = SchoolAgendaEvent.day(lessons: [], courses: [series], on: autumn, calendar: calendar)
        #expect(result.count == 3)
        #expect(result.map(\.start) == Array(instants.prefix(3)).map { SchoolLesson.date($0) })
        #expect(SchoolAgendaMonth.dayIdentifier(result[0].start!, calendar: calendar) == "agenda-day-2026-10-25")
        let next = SchoolAgendaEvent.day(lessons: [], courses: [series], on: day, calendar: calendar)
        #expect(next.count == 1)
    }

    private func lesson(id: Int, start: String, end: String) throws -> SchoolLesson {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson())) as! [String: Any]
        object["id"] = identifier(id).uuidString; object["plannedStart"] = start; object["plannedEnd"] = end
        return try JSONDecoder().decode(SchoolLesson.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func identifier(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "11111111-1111-4111-8111-%012d", value))!
    }
    private func occurrence(_ id: Int, hour: Int, instructor: UUID? = nil) -> SchoolCourseOccurrence {
        occurrence(id, start: String(format: "2026-10-26T%02d:00:00Z", hour - 1),
            end: String(format: "2026-10-26T%02d:00:00Z", hour), instructor: instructor)
    }
    private func occurrence(_ id: Int, start: String, end: String, instructor: UUID? = nil) -> SchoolCourseOccurrence {
        SchoolCourseOccurrence(id: identifier(id), position: id, startsAt: start, endsAt: end, timeZone: "Europe/Zurich",
            instructorMembershipId: instructor ?? identifier(500), instructorDisplayName: "Camille Exemple", attendanceRequired: true)
    }
    private func course(id: Int = 1, status: SchoolCourseSeries.Status = .published,
                        occurrences: [SchoolCourseOccurrence]? = nil) -> SchoolCourseSeries {
        let sessions = occurrences ?? [occurrence(1, hour: 9)]
        return SchoolCourseSeries(id: identifier(id), schoolId: identifier(400), version: 1, status: status,
            typeId: identifier(450), typeTitle: "Sensibilisation", title: "Sensibilisation", description: "", location: "Salle",
            conditions: "", teachingLanguage: nil, responsibleMembershipId: identifier(500), responsibleDisplayName: "Camille Exemple",
            capacity: 10, seatsTaken: 0, remainingSeats: 10, minParticipants: nil, policyVersion: 1, selfCancelHours: 24,
            selfCancellationDeadline: sessions[0].startsAt, firstStartsAt: sessions[0].startsAt, lastEndsAt: sessions.last!.endsAt,
            totalMinutes: sessions.count * 60, publishedAt: status == .draft ? nil : "2026-10-01T08:00:00Z", occurrences: sessions, canManage: true)
    }
}

/// Barrière sans délai : chaque réponse est libérée explicitement par le test.
@MainActor private final class AgendaCourseReadGate {
    private var pending: [Int: CheckedContinuation<[SchoolCourseSeries], any Error>] = [:]
    private var starts: [Int: CheckedContinuation<Void, Never>] = [:]
    func fetch(_ id: Int) async throws -> [SchoolCourseSeries] {
        try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            starts.removeValue(forKey: id)?.resume()
        }
    }
    func waitForStart(_ id: Int) async {
        if pending[id] != nil { return }
        await withCheckedContinuation { starts[id] = $0 }
    }
    func finish(_ id: Int, with value: [SchoolCourseSeries]) {
        pending.removeValue(forKey: id)?.resume(returning: value)
    }
}
