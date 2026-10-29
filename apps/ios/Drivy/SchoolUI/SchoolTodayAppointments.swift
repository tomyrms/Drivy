import Foundation

/// Même chronologie et mêmes occurrences que l’agenda, ordonnées pour le terrain.
enum SchoolTodayAppointments {
    static func ordered(lessons: [SchoolLesson], unfinished: [SchoolLesson], courses: [SchoolCourseSeries],
        on day: Date, calendar: Calendar, instructorID: UUID?, captureLessonID: UUID?, now: Date) -> [SchoolAgendaEvent] {
        // Une publication n’est jamais un engagement d’élève. Ici seuls les cours attribués au moniteur
        // sont ajoutés ; l’espace élève garde sa projection personnelle d’inscriptions.
        let assigned = instructorID == nil ? [] : courses.filter { $0.status == .published }
        let daily = SchoolAgendaEvent.day(lessons: lessons, courses: assigned, on: day,
            calendar: calendar, instructorID: instructorID)
        let candidates = daily + unfinished.map(SchoolAgendaEvent.lesson)
        var seen = Set<String>()
        return candidates.filter { event in
            guard seen.insert(event.id).inserted else { return false }
            switch event {
            case .lesson(let lesson): return lesson.status == "PLANNED"
            case .course(let item): return item.occurrence.end.map { $0 > now } ?? false
            }
        }.sorted {
            let left = priority($0, dayStart: calendar.startOfDay(for: day), captureLessonID: captureLessonID, now: now)
            let right = priority($1, dayStart: calendar.startOfDay(for: day), captureLessonID: captureLessonID, now: now)
            if left != right { return left < right }
            if $0.start != $1.start { return ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            return $0.id < $1.id
        }
    }

    private static func priority(_ event: SchoolAgendaEvent, dayStart: Date, captureLessonID: UUID?, now: Date) -> Int {
        switch event {
        case .lesson(let lesson):
            if lesson.id == captureLessonID { return 0 }
            if lesson.hasStarted { return (lesson.startsAt ?? dayStart) >= dayStart ? 1 : 2 }
            return SchoolLessonHubRules.isMissed(lesson, now: now) ? 5 : 4
        case .course(let item):
            return item.occurrence.start.map { $0 <= now } == true ? 3 : 4
        }
    }
}
