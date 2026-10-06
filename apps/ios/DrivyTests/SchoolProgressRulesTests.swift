import Foundation
import Testing
@testable import Drivy

/// La Progression range ce que le serveur a publié ; elle ne calcule ni score ni tendance.
struct SchoolProgressRulesTests {
    private func item(_ label: String, _ level: String, observedAt: String = "2026-09-20T10:00:00Z",
                      id: UUID = UUID(), lesson: UUID = UUID(), revision: UUID = UUID()) -> SchoolReportProgressItem {
        SchoolReportProgressItem(competencyId: id, sourceLessonId: lesson, sourceRevisionId: revision,
            label: label, level: level, context: "", observedAt: observedAt)
    }

    private func lesson(_ id: UUID, start: String, status: String = "COMPLETED", revision: UUID? = nil) throws -> SchoolLesson {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson(status: status))) as! [String: Any]
        value["id"] = id.uuidString
        value["plannedStart"] = start
        value["plannedEnd"] = start.replacingOccurrences(of: ":00:00Z", with: ":50:00Z")
        if let revision { value["currentPublishedRevisionId"] = revision.uuidString }
        return try JSONDecoder().decode(SchoolLesson.self, from: JSONSerialization.data(withJSONObject: value))
    }

    @Test func countLineNamesOnlyTheGroupsThatExist() {
        let items = [item("a", "INDEPENDENT"), item("b", "INDEPENDENT"), item("c", "GUIDED"), item("d", "DISCOVERING")]
        #expect(SchoolProgressRules.countLine(items: items, unobserved: 5)
            == "2 en autonomie · 1 avec accompagnement · 1 en découverte · 5 pas encore vues")
        #expect(SchoolProgressRules.countLine(items: [item("a", "GUIDED")], unobserved: 0) == "1 avec accompagnement")
        #expect(SchoolProgressRules.countLine(items: [], unobserved: 1) == "1 pas encore vue")
        #expect(SchoolProgressRules.countLine(items: [], unobserved: 0) == nil)
    }

    @Test func toWorkOnPutsDiscoveryFirstThenTheOldestObservation() {
        let items = [
            item("Vitesse", "GUIDED", observedAt: "2026-09-01T10:00:00Z"),
            item("Giratoire", "DISCOVERING", observedAt: "2026-09-10T10:00:00Z"),
            item("Stationnement", "INDEPENDENT", observedAt: "2026-08-01T10:00:00Z"),
            item("Priorité", "DISCOVERING", observedAt: "2026-09-02T10:00:00Z"),
            item("Anticipation", "GUIDED", observedAt: "2026-08-15T10:00:00Z")
        ]
        #expect(SchoolProgressRules.toWorkOn(items).map(\.label) == ["Priorité", "Giratoire", "Anticipation", "Vitesse"])
    }

    @Test func independentFollowsTheCurriculumOrder() {
        let first = UUID(), second = UUID()
        let items = [item("Zèbre", "INDEPENDENT"), item("B", "INDEPENDENT", id: second), item("A", "INDEPENDENT", id: first),
                     item("Hors groupe", "GUIDED")]
        #expect(SchoolProgressRules.independent(items, order: [second, first]).map(\.label) == ["B", "A", "Zèbre"])
    }

    @Test func workedCompetenciesAreThoseWhoseLevelComesFromTheLesson() {
        let lessonID = UUID(), first = UUID(), second = UUID()
        let items = [item("Vitesse", "GUIDED", id: second, lesson: lessonID), item("Giratoire", "DISCOVERING", id: first, lesson: lessonID),
                     item("Ailleurs", "INDEPENDENT")]
        #expect(SchoolProgressRules.worked(in: lessonID, items: items, order: [first, second]).map(\.label) == ["Giratoire", "Vitesse"])
        #expect(SchoolProgressRules.worked(in: UUID(), items: items, order: []).isEmpty)
    }

    @Test func lastEvaluatedIsTheMostRecentLessonWithAPublishedReportOnceEverythingIsRead() throws {
        let old = UUID(), recent = UUID(), oldRevision = UUID(), recentRevision = UUID()
        let lessons = [
            try lesson(old, start: "2026-09-01T08:00:00Z", revision: oldRevision),
            try lesson(recent, start: "2026-09-20T08:00:00Z", revision: recentRevision),
            // Terminée sans bilan partagé, et planifiée : aucune des deux n’est une leçon évaluée.
            try lesson(UUID(), start: "2026-09-25T08:00:00Z"),
            try lesson(UUID(), start: "2026-09-27T08:00:00Z", status: "PLANNED", revision: UUID())
        ]
        let source = try #require(SchoolProgressRules.lastEvaluated(lessons: lessons, hasMore: false,
            items: [item("Vitesse", "GUIDED", lesson: old, revision: oldRevision)]))
        #expect(source.lessonID == recent && source.revisionID == recentRevision)
        #expect(source.date == "2026-09-20T08:00:00Z" && source.timeZone == "Europe/Zurich")
    }

    @Test func lastEvaluatedFollowsTheNewestEvaluationWhileOlderPagesHideRecentLessons() throws {
        let read = UUID(), readRevision = UUID(), unread = UUID(), unreadRevision = UUID()
        let lessons = [try lesson(read, start: "2026-01-10T08:00:00Z", revision: readRevision)]
        let items = [item("Vitesse", "GUIDED", observedAt: "2026-01-10T09:00:00Z", lesson: read, revision: readRevision),
                     item("Giratoire", "DISCOVERING", observedAt: "2026-09-20T09:00:00Z", lesson: unread, revision: unreadRevision)]
        let source = try #require(SchoolProgressRules.lastEvaluated(lessons: lessons, hasMore: true, items: items))
        #expect(source.lessonID == unread && source.revisionID == unreadRevision)
        #expect(source.date == "2026-09-20T09:00:00Z" && source.timeZone == nil)
        // La leçon source est déjà lue : sa révision en cours et sa date font foi.
        let corrected = UUID()
        let known = [try lesson(read, start: "2026-01-10T08:00:00Z", revision: corrected)]
        let fromLesson = try #require(SchoolProgressRules.lastEvaluated(lessons: known, hasMore: true, items: [items[0]]))
        #expect(fromLesson.revisionID == corrected && fromLesson.date == "2026-01-10T08:00:00Z")
    }

    @Test func nothingIsEvaluatedWithoutAPublishedReportOrAnEvaluation() throws {
        let lessons = [try lesson(UUID(), start: "2026-09-25T08:00:00Z")]
        #expect(SchoolProgressRules.lastEvaluated(lessons: lessons, hasMore: false, items: []) == nil)
        #expect(SchoolProgressRules.lastEvaluated(lessons: [], hasMore: true, items: []) == nil)
        // Sans leçon lue, l’évaluation la plus récente désigne sa source.
        let only = item("Vitesse", "GUIDED")
        #expect(SchoolProgressRules.lastEvaluated(lessons: [], hasMore: false, items: [only])?.lessonID == only.sourceLessonId)
    }
}
