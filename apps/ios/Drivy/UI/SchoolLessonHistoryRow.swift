import SwiftUI

/// The row of a lesson in a history: the learner's dossier and the lessons of the instructor.
/// Times, then the date (dossier) or the learner (instructor's history) as the title. The first
/// detail line says what is unusual, then the date when the title is a name, the permit when the
/// list mixes several, and the instructor when the reader is someone else. The last line says in
/// words what the lesson holds (« Bilan · Trajet »). The meeting point stays in the lesson itself.
struct SchoolLessonHistoryRow: View {
    enum Title { case day, learner }

    let lesson: SchoolLesson
    var title: Title = .day
    /// Named only when the list mixes several permits.
    var permit: String? = nil
    /// Named only when the instructor is not the reader.
    var instructor: String? = nil
    var showsState = true

    var body: some View {
        DrivyLessonRow(start: SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone),
            end: SchoolTrainingFormatting.time(lesson.plannedEnd, zone: lesson.timeZone),
            title: Self.titleText(lesson, title: title),
            details: [Self.detail(lesson, title: title, permit: permit, instructor: instructor)],
            state: showsState ? lesson.drivyState : nil,
            contents: lesson.drivyContents)
    }

    private static func day(_ lesson: SchoolLesson) -> String {
        SchoolTrainingFormatting.rowDay(lesson.plannedStart, zone: lesson.timeZone)
    }

    static func titleText(_ lesson: SchoolLesson, title: Title) -> String {
        switch title {
        case .day: day(lesson)
        case .learner: lesson.providedLearnerName ?? "Élève"
        }
    }

    /// One line, its parts joined by a middle dot; empty when there is nothing to add to the title.
    static func detail(_ lesson: SchoolLesson, title: Title, permit: String?, instructor: String?) -> String {
        let parts = [title == .learner ? day(lesson) : nil, permit, instructor]
        return parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
