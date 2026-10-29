import Foundation
import Testing
@testable import Drivy

struct SchoolProgressReadingTests {
    private func competency(_ label: String, id: UUID = UUID(), order: Int = 0,
                            description: String = "Définition du référentiel.") -> SchoolCatalogCompetency {
        SchoolCatalogCompetency(id: id, schoolId: UUID(), version: 1, curriculumVersionId: UUID(),
            key: id.uuidString, label: label, description: description, sortOrder: order)
    }

    private func item(_ competency: SchoolCatalogCompetency, level: String) -> SchoolReportProgressItem {
        SchoolReportProgressItem(competencyId: competency.id, sourceLessonId: UUID(), sourceRevisionId: UUID(),
            label: competency.label, level: level, context: "Contexte conservé", observedAt: "2026-09-20T23:30:00Z")
    }

    private func progress(_ items: [SchoolReportProgressItem], unseen: [UUID] = []) -> SchoolReportProgress {
        SchoolReportProgress(trainingId: UUID(), items: items, unobservedCompetencyIds: unseen,
            computedAt: "2026-10-29T12:00:00Z")
    }

    @Test func searchFindsAllThreeGroupsWithoutCaseOrAccentRestrictions() {
        let guided = competency("Équilibre en circulation"), independent = competency("Équilibre au pas")
        let unseen = competency("Équilibre à l’arrêt")
        let value = progress([item(guided, level: "GUIDED"), item(independent, level: "INDEPENDENT")], unseen: [unseen.id])
        let result = SchoolProgressReading(progress: value, curriculum: [guided, independent, unseen], query: "  EQUILIBRE  ")
        #expect(result.isSearching && result.resultCount == 3)
        #expect(result.toWorkOn.map(\.id) == [guided.id])
        #expect(result.independent.map(\.id) == [independent.id])
        #expect(result.unseen.map(\.id) == [unseen.id])
        #expect(result.missingReferenceCount == 0)
    }

    @Test func referenceLabelWinsOverAnOlderEvaluationLabelAndKeepsItsFullSearchableName() {
        let current = competency("Anticipation et partage de la route")
        let old = competency("Ancien libellé", id: current.id)
        let evaluation = item(old, level: "GUIDED")
        let value = progress([evaluation])
        let match = SchoolProgressReading(progress: value, curriculum: [current], query: "PARTAGE")
        #expect(match.resultCount == 1 && match.label(evaluation) == "Anticipation")
        #expect(match.toWorkOn.first == evaluation)
        #expect(SchoolProgressReading(progress: value, curriculum: [current], query: "ancien").resultCount == 0)
    }

    @Test func searchNeverAddsAnotherCurriculumCompetencyToTheAuthorizedProjection() {
        let own = competency("Priorités"), foreign = competency("Équilibre")
        let value = progress([], unseen: [own.id])
        let result = SchoolProgressReading(progress: value, curriculum: [own, foreign], query: "equilibre")
        #expect(result.resultCount == 0)
        #expect(result.missingReferenceCount == 0)
        let cleared = SchoolProgressReading(progress: value, curriculum: [own, foreign], query: "")
        #expect(cleared.unseen.map(\.id) == [own.id])
    }

    @Test func missingReferenceKeepsOnlyKnownEvaluationLabelsAndReportsIncompleteCoverage() {
        let known = competency("Priorités"), missing = UUID()
        let evaluation = item(known, level: "GUIDED")
        let value = progress([evaluation], unseen: [missing])
        let result = SchoolProgressReading(progress: value, curriculum: [], query: "priorites")
        #expect(result.resultCount == 1 && result.toWorkOn == [evaluation])
        #expect(result.missingReferenceCount == 2 && result.unseen.isEmpty)
        let absent = SchoolProgressReading(progress: value, curriculum: [], query: "stationnement")
        #expect(absent.resultCount == 0 && absent.missingReferenceCount == 2)
        let restored = SchoolProgressReading(progress: value, curriculum: [known], query: "")
        #expect(restored.missingReferenceCount == 1 && restored.resultCount == 1)
    }

    @Test func clearingTheQueryRestoresTheWholeProjectionInItsOriginalPedagogicalOrder() {
        let first = competency("Zèbre", order: 0), second = competency("Autoroute", order: 1)
        let guided = competency("Priorités", order: 2), unseen = competency("Stationnement", order: 3)
        let value = progress([item(second, level: "INDEPENDENT"), item(first, level: "INDEPENDENT"),
            item(guided, level: "GUIDED")], unseen: [unseen.id])
        let curriculum = [unseen, second, guided, first]
        #expect(SchoolProgressReading(progress: value, curriculum: curriculum, query: "autoroute").resultCount == 1)
        let restored = SchoolProgressReading(progress: value, curriculum: curriculum, query: " \n ")
        #expect(!restored.isSearching && restored.resultCount == 4)
        #expect(restored.independent.map(\.id) == [first.id, second.id])
        #expect(restored.toWorkOn == [value.items[2]])
        #expect(restored.unseen.map(\.id) == [unseen.id])
        #expect(restored.toWorkOn.first?.observedAt == "2026-09-20T23:30:00Z")
        #expect(restored.toWorkOn.first?.sourceLessonId == value.items[2].sourceLessonId)
    }

    @Test func definitionsAreOnlyTheExistingNonblankReferenceText() {
        #expect(SchoolProgressReading.definition(competency("Priorités", description: " \n ")) == nil)
        let content = "Repérer les priorités.\nContrôler les deux côtés."
        #expect(SchoolProgressReading.definition(competency("Priorités", description: " \n\(content)\n ")) == content)
    }

    @MainActor @Test func observationDateUsesSchoolDayWithoutTodayOrRefreshFallback() {
        #expect(SchoolTrainingFormatting.day("2026-09-20T23:30:00Z", zone: "Europe/Zurich") == "21 septembre 2026")
        #expect(SchoolTrainingFormatting.day("2026-09-20T23:30:00Z", zone: "UTC") == "20 septembre 2026")
        #expect(SchoolTrainingFormatting.day("", zone: "Europe/Zurich") == "Date indisponible")
        #expect(SchoolTrainingFormatting.day("2026-09-20T23:30:00Z", zone: "Invalid/Zone") == "Date indisponible")
    }
}
