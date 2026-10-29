import Foundation
import Observation

/// Projection commune aux résultats et à la recherche du prochain engagement.
/// Les requêtes nominatives restent en mémoire : aucun paramètre réseau ni stockage.
enum SchoolAgendaDiscovery {
    static func events(lessons: [SchoolLesson], courses: [SchoolCourseSeries], range: SchoolAgendaRange,
                       instructorID: UUID?) -> [SchoolAgendaEvent] {
        let lessons = lessons.filter { instructorID == nil || $0.instructorMembershipId == instructorID }
        let occurrences = courses.flatMap { series in
            series.occurrences.filter { instructorID == nil || $0.instructorMembershipId == instructorID }
                .map { SchoolAgendaEvent.course(SchoolAgendaCourseItem(series: series, occurrence: $0)) }
        }
        var seen = Set<String>()
        return (lessons.map(SchoolAgendaEvent.lesson) + occurrences)
            .filter { $0.start.map(range.contains) == true && seen.insert($0.id).inserted }
            .sorted { $0.start == $1.start ? $0.id < $1.id : ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    static func matches(_ text: String, query: String) -> Bool {
        func fold(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CH"))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let words = fold(query).split(separator: " "), value = fold(text)
        return words.allSatisfy { value.contains($0) }
    }

    static func next(in events: [SchoolAgendaEvent]) -> SchoolAgendaEvent? {
        events.first { event in
            switch event {
            case .lesson(let lesson): lesson.status == "PLANNED"
            case .course(let item): item.series.status == .published
            }
        }
    }
}

/// Trois fenêtres de 30 jours au plus ; une source tronquée interdit de conclure
/// au prochain rendez-vous. Chaque résultat reste attaché à la portée du départ.
@MainActor @Observable final class SchoolAgendaNextSearch {
    private(set) var isLoading = false
    private(set) var message: String?
    private(set) var searchedRange: SchoolAgendaRange?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func cancel(clear: Bool = false) {
        generation = UUID(); task?.cancel(); task = nil
        if isLoading { message = "Recherche interrompue." }
        isLoading = false
        if clear { message = nil; searchedRange = nil }
    }

    func start(after day: Date, calendar: Calendar, instructorID: UUID?,
        isCurrent: @escaping @MainActor () -> Bool,
        lessons: @escaping @MainActor (SchoolAgendaRange) async throws -> [SchoolLesson]?,
        courses: @escaping @MainActor (SchoolAgendaRange) async throws -> [SchoolCourseSeries],
        onFound: @escaping @MainActor (Date) -> Void,
        onAccessFailure: @escaping @MainActor () async -> Void) {
        cancel(clear: true)
        guard let start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)),
              let end = calendar.date(byAdding: .day, value: 90, to: start) else { return }
        searchedRange = SchoolAgendaRange(start: start, end: end)
        let id = generation
        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == id { isLoading = false; task = nil } }
            do {
                for offset in [0, 30, 60] {
                    try Task.checkCancellation()
                    guard isCurrent(), generation == id,
                          let from = calendar.date(byAdding: .day, value: offset, to: start),
                          let to = calendar.date(byAdding: .day, value: 30, to: from) else { return }
                    let range = SchoolAgendaRange(start: from, end: to)
                    guard let lessonRows = try await lessons(range) else { return }
                    try Task.checkCancellation()
                    guard generation == id, isCurrent() else { return }
                    let series = try await courses(range)
                    guard !Task.isCancelled, generation == id, isCurrent() else { return }
                    guard series.count < 200 else {
                        message = "Recherche incomplète : certaines séances de cours peuvent manquer. Réduis la période dans l’agenda."
                        return
                    }
                    let events = SchoolAgendaDiscovery.events(lessons: lessonRows, courses: series, range: range, instructorID: instructorID)
                    if let date = SchoolAgendaDiscovery.next(in: events)?.start { onFound(date); return }
                }
                message = "Aucun rendez-vous dans les 90 jours recherchés."
            } catch {
                guard !Task.isCancelled, generation == id, isCurrent() else { return }
                let agenda = error as? SchoolAgendaFailure, planning = error as? SchoolPlanningFailure
                if agenda == .authentication || agenda == .forbidden || planning == .unauthorized || planning == .forbidden || planning == .notFound {
                    cancel(clear: true)
                    await onAccessFailure()
                } else {
                    message = "Recherche incomplète. La lecture des rendez-vous a échoué. Réessaie."
                }
            }
        }
    }
}
