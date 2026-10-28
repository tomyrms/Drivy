import Foundation
import Testing
@testable import Drivy

struct SchoolReportCompetencyGroupsTests {
    private let schoolID = UUID(uuidString: "71000000-0000-4000-8000-000000000001")!
    private let curriculumID = UUID(uuidString: "71000000-0000-4000-8000-000000000002")!

    @Test func groupingKeepsEveryAuthorizedHistoricalCompetencyExactlyOnce() {
        let values = (0..<5).map(competency)
        let unknownID = UUID()
        let groups = SchoolReportFlowRules.competencyGroups(values,
            relevantIDs: [values[3].id, values[1].id, unknownID])
        #expect(groups.relevant == [values[1], values[3]])
        #expect(groups.others == [values[0], values[2], values[4]])
        #expect(Set((groups.relevant + groups.others).map(\.id)) == Set(values.map(\.id)))
        #expect((groups.relevant + groups.others).allSatisfy { $0.curriculumVersionId == curriculumID && $0.version == 2 })
    }

    @Test func anEmptyLessonDoesNotInventRelevantCompetencies() {
        let values = (0..<3).map(competency)
        let ids = SchoolReportFlowRules.relevantCompetencyIDs(evaluations: [], observations: [], goals: [])
        let groups = SchoolReportFlowRules.competencyGroups(values, relevantIDs: ids)
        #expect(groups.relevant.isEmpty)
        #expect(groups.others == values)
    }

    @Test func explicitLinksSuggestACompetencyWithoutInventingAnEvaluation() {
        let values = (0..<3).map(competency)
        let evaluations = [SchoolReportObservation(competencyId: values[0].id, level: "GUIDED", context: "À l’arrêt")]
        let observation = SchoolObservation(id: UUID(), schoolId: schoolID, version: 1, lessonId: UUID(),
            trainingId: UUID(), draftId: nil, captureId: nil, segmentId: nil, pointSequence: nil,
            competencyId: values[1].id, text: "Observation synthétique", origin: "LIVE", observedAt: "2026-10-28T12:00:00Z",
            eventKind: "QUALIFIED", eventStatus: "POSITIVE", authorMembershipId: UUID())
        let ids = SchoolReportFlowRules.relevantCompetencyIDs(evaluations: evaluations, observations: [observation],
            goals: [SchoolLessonGoal(label: "Objectif synthétique", competencyId: values[2].id)])
        #expect(ids == Set(values.map(\.id)))
        #expect(evaluations.count == 1 && evaluations[0].level == "GUIDED")
    }

    private func competency(_ order: Int) -> SchoolCatalogCompetency {
        SchoolCatalogCompetency(id: UUID(), schoolId: schoolID, version: 2, curriculumVersionId: curriculumID,
            key: "competency-\(order)", label: "Compétence \(order)", description: "", sortOrder: order)
    }
}
