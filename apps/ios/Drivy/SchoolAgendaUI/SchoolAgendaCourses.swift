import Foundation
import Observation

/// Lecture indépendante des cours : une réponse de leçons ne valide jamais cette source.
@MainActor @Observable final class SchoolAgendaCourses {
    enum State: Equatable {
        case idle, loading, loaded, partial, failed(String)
    }

    private(set) var state: State = .idle
    private(set) var scope: SchoolAgendaScope?
    private(set) var readAt: Date?
    private(set) var items: [SchoolCourseSeries] = []
    @ObservationIgnored private var requestID = UUID()

    func items(in wanted: SchoolAgendaScope) -> [SchoolCourseSeries] { scope == wanted ? items : [] }
    func isComplete(in wanted: SchoolAgendaScope) -> Bool { scope == wanted && state == .loaded }
    func isLoading(in wanted: SchoolAgendaScope) -> Bool { scope != wanted || state == .idle || state == .loading }

    func error(in wanted: SchoolAgendaScope, timeZone: String) -> String? {
        guard scope == wanted else { return nil }
        switch state {
        case .partial:
            return "Cours partiellement chargés. Certaines séances peuvent manquer."
        case .failed(let reason):
            let retained = readAt.map { " Dernière lecture réussie le \(SchoolDateFormat.template("dMMMMyHHmm", $0, zone: timeZone))." } ?? ""
            return "Cours non actualisés. \(reason)\(retained)"
        default: return nil
        }
    }

    func reset() {
        requestID = UUID(); scope = nil; state = .idle; items = []; readAt = nil
    }

    /// Retourne vrai seulement si un refus d'accès courant demande une relecture du compte.
    @discardableResult func load(scope wanted: SchoolAgendaScope,
        isCurrent: @MainActor () -> Bool = { true },
        fetch: @MainActor () async throws -> [SchoolCourseSeries]) async -> Bool {
        let id = UUID(); requestID = id
        if scope != wanted { items = []; readAt = nil }
        scope = wanted; state = .loading
        defer { if requestID == id && state == .loading { state = .idle } }
        do {
            let fresh = try await fetch()
            guard !Task.isCancelled, requestID == id, isCurrent() else { return false }
            items = fresh; readAt = Date()
            // Le contrat actuel borne la liste à 200 sans curseur : à la borne,
            // aucune exhaustivité de la journée ne peut être affirmée.
            state = fresh.count >= 200 ? .partial : .loaded
        } catch {
            guard requestID == id, isCurrent() else { return false }
            if Task.isCancelled || error is CancellationError {
                state = .idle
                return false
            }
            if let failure = error as? SchoolPlanningFailure,
               failure == .unauthorized || failure == .forbidden || failure == .notFound {
                items = []; readAt = nil
                state = .failed(failure.errorDescription ?? "Tes accès ont changé.")
                return true
            }
            state = .failed("Réessaie pour retrouver les cours de cette période.")
        }
        return false
    }
}

/// Une seule chronologie pour les lignes, les marques du calendrier et les résumés.
enum SchoolAgendaEvent: Identifiable, Equatable, Sendable {
    case lesson(SchoolLesson)
    case course(SchoolAgendaCourseItem)

    var id: String {
        switch self {
        case .lesson(let lesson): "lesson:\(lesson.id.uuidString)"
        case .course(let item): "course:\(item.series.id.uuidString):\(item.occurrence.id.uuidString)"
        }
    }
    var start: Date? {
        switch self { case .lesson(let value): value.startsAt; case .course(let value): value.occurrence.start }
    }
    var end: Date? {
        switch self { case .lesson(let value): value.endsAt; case .course(let value): value.occurrence.end }
    }

    static func day(lessons: [SchoolLesson], courses: [SchoolCourseSeries], on day: Date,
        calendar: Calendar, instructorID: UUID? = nil) -> [Self] {
        let lessons = lessons.filter { $0.startsAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
        let courses = SchoolAgendaCourseItem.items(courses, on: day, calendar: calendar)
            .filter { instructorID == nil || $0.occurrence.instructorMembershipId == instructorID }
        var seen = Set<String>()
        return (lessons.map(Self.lesson) + courses.map(Self.course))
            .filter { seen.insert($0.id).inserted }
            .sorted {
                if $0.start != $1.start { return ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
                if $0.end != $1.end { return ($0.end ?? .distantFuture) < ($1.end ?? .distantFuture) }
                return $0.id < $1.id
            }
    }

    @MainActor static func summary(_ events: [Self], isComplete: Bool) -> SchoolAgendaDaySummary {
        var result = SchoolAgendaDaySummary(isComplete: isComplete)
        for event in events {
            switch event {
            case .lesson(let value):
                if value.drivyState.isClosed { result.closed += 1 } else { result.active += 1 }
            case .course(let item):
                switch item.series.status {
                case .draft: result.courseDraft += 1
                case .cancelled: result.courseClosed += 1
                case .published, .closed: result.courseActive += 1
                }
            }
        }
        return result
    }
}
