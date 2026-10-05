import Foundation
import Testing
@testable import Drivy

/// Rédaction du bilan en étapes : pas d’étape vide, un ordre tenu à un seul endroit, une saisie gardée sur
/// l’appareil sans jamais l’envoyer avant le geste final. Toutes les données sont synthétiques.
@MainActor struct SchoolReportFlowTests {
    private static let draftID = UUID(uuidString: "70000000-0000-4000-8000-000000000050")!

    // MARK: Étapes

    @Test(arguments: [
        SchoolReportStepCase(hasTrip: true, observations: 2, competencies: 9, expected: [.trip, .competencies, .report]),
        SchoolReportStepCase(hasTrip: false, observations: 0, competencies: 9, expected: [.competencies, .report]),
        SchoolReportStepCase(hasTrip: false, observations: 3, competencies: 9, expected: [.trip, .competencies, .report]),
        SchoolReportStepCase(hasTrip: true, observations: 0, competencies: 0, expected: [.trip, .report]),
        SchoolReportStepCase(hasTrip: false, observations: 0, competencies: 0, expected: [.report])
    ])
    func noStepIsEverEmpty(_ value: SchoolReportStepCase) {
        #expect(SchoolReportFlowRules.steps(hasTrip: value.hasTrip, observationCount: value.observations,
            competencyCount: value.competencies) == value.expected)
    }

    @Test func theOrderIsDecidedInOnePlaceAndTheReportComesLast() {
        #expect(SchoolReportFlowRules.order == [.trip, .competencies, .report])
        #expect(Set(SchoolReportFlowRules.order) == Set(SchoolReportStep.allCases))
        let all = SchoolReportFlowRules.steps(hasTrip: true, observationCount: 1, competencyCount: 1)
        #expect(all == SchoolReportFlowRules.order)
    }

    @Test func positionIsSilentForASingleStep() {
        #expect(SchoolReportFlowRules.position(of: 1, count: 3) == "2 sur 3")
        #expect(SchoolReportFlowRules.position(of: 0, count: 1) == nil)
        #expect(SchoolReportFlowRules.position(of: 3, count: 3) == nil)
    }

    @Test func aStepWithoutTripIsNamedAfterItsObservations() {
        #expect(SchoolReportFlowRules.title(of: .trip, hasTrip: true) == "Trajet")
        #expect(SchoolReportFlowRules.title(of: .trip, hasTrip: false) == "Observations")
        #expect(SchoolReportFlowRules.title(of: .report, hasTrip: false) == "Bilan")
    }

    @Test func theEntryLabelSaysWhatTheGestureDoes() {
        #expect(SchoolReportFlowRules.editTitle(isEmpty: true, unsaved: false) == "Rédiger le bilan")
        #expect(SchoolReportFlowRules.editTitle(isEmpty: false, unsaved: false) == "Modifier le bilan")
        #expect(SchoolReportFlowRules.editTitle(isEmpty: false, unsaved: true) == "Reprendre le bilan")
    }

    // MARK: Compétences

    @Test func competenciesOfTheLessonComeFirstAndTheOthersStayReachable() {
        let all = (1...4).map { Self.competency($0) }
        let groups = SchoolReportFlowRules.competencyGroups(all,
            observations: [Self.observation(competency: all[2].id, status: "ATTENTION")],
            goals: [SchoolLessonGoal(label: "Priorités", competencyId: all[0].id)],
            saved: [])
        #expect(groups.worked.map(\.id) == [all[0].id, all[2].id])
        #expect(groups.others.map(\.id) == [all[1].id, all[3].id])
    }

    @Test func withoutAnyMarkTheListStaysWholeAndFlat() {
        let all = (1...3).map { Self.competency($0) }
        let none = SchoolReportFlowRules.competencyGroups(all, observations: [], goals: [], saved: [])
        #expect(none.worked == all && none.others.isEmpty)
        let every = SchoolReportFlowRules.competencyGroups(all, observations: [], goals: [],
            saved: all.map { SchoolReportObservation(competencyId: $0.id, level: "GUIDED", context: "") })
        #expect(every.worked == all && every.others.isEmpty)
    }

    @Test func signalsMadeOnTheRoadAreRecalledOncePerAppraisal() {
        let id = UUID()
        let observations = [Self.observation(competency: id, status: "ATTENTION"), Self.observation(competency: id, status: "POSITIVE"),
                            Self.observation(competency: id, status: "ATTENTION"), Self.observation(competency: UUID(), status: "TO_REWORK")]
        #expect(SchoolReportFlowRules.signalled(for: id, in: observations) == "En route\u{00A0}: Attention, Point positif")
        #expect(SchoolReportFlowRules.signalled(for: UUID(), in: observations) == nil)
    }

    // MARK: Brouillon local chiffré

    @Test func theLocalDraftRoundTripsEncryptedAndOnlyForItsAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drivy-report-drafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolReportDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        let draft = Self.localDraft(edited: "Créneau en marche arrière")
        #expect(try store.read(scope: scope, draftID: draft.draftID) == nil)
        try store.save(draft, scope: scope)
        #expect(try store.read(scope: scope, draftID: draft.draftID) == draft)

        let file = directory.appendingPathComponent("\(draft.draftID.uuidString.lowercased()).bin")
        let bytes = try Data(contentsOf: file)
        #expect(bytes.range(of: Data("Créneau".utf8)) == nil)

        let other = SchoolCommandScope(personID: UUID(), schoolID: scope.schoolID, membershipID: scope.membershipID,
            accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL)
        #expect(throws: SchoolConfigurationFailure.storage) { _ = try store.read(scope: other, draftID: draft.draftID) }
        let otherKey = EncryptedSchoolReportDraftStore(directory: directory, keyData: Data(repeating: 9, count: 32))
        #expect(throws: SchoolConfigurationFailure.storage) { _ = try otherKey.read(scope: scope, draftID: draft.draftID) }

        try store.remove(scope: scope, draftID: draft.draftID)
        #expect(try store.read(scope: scope, draftID: draft.draftID) == nil)
    }

    // MARK: Saisie gardée et reprise

    @Test func typingIsKeptOnTheDeviceAndNothingIsSentBeforeTheFinalGesture() async throws {
        let server = LessonFinishServer(), outbox = ConfigurationOutboxStub(), drafts = LocalDraftStub()
        let model = workspace(server, outbox: outbox, drafts: drafts)
        await model.load()
        model.persistLocalDraft()
        #expect(drafts.values.isEmpty)
        model.nextStep = "Reprendre les giratoires."
        model.persistLocalDraft()
        let kept = try #require(drafts.values[Self.draftID])
        #expect(kept.edited.nextStep == "Reprendre les giratoires." && kept.base.isEmpty)
        #expect(outbox.saves.isEmpty)
        #expect(await server.requests().allSatisfy { $0.httpMethod != "PUT" && $0.httpMethod != "POST" })
    }

    @Test func aKeptEntryComesBackWhenTheSchoolIsWhereItWasLeft() async {
        let drafts = LocalDraftStub()
        drafts.values[Self.draftID] = Self.localDraft(edited: "Texte repris après fermeture")
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        #expect(model.workedOn == "Texte repris après fermeture")
        #expect(model.reportEdited && model.hasLocalEdits && !model.needsReload && model.canMutate)
    }

    @Test func aKeptEntryIsNeverLostNorSilentlyRebasedWhenTheSchoolMoved() async {
        let drafts = LocalDraftStub()
        drafts.values[Self.draftID] = Self.localDraft(base: "Ancienne version de l’école", edited: "Ma saisie")
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        #expect(model.workedOn == "Ma saisie" && model.needsReload && !model.canMutate)
        #expect(model.retainedEditsText.contains("Ma saisie"))
        await model.load(discardingEdits: true)
        #expect(model.workedOn.isEmpty && !model.needsReload && drafts.values.isEmpty)
    }

    @Test func theKeptEntryIsErasedOnlyAfterTheDurableReceipt() async throws {
        let server = LessonFinishServer(), drafts = LocalDraftStub()
        let model = workspace(server, outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        model.observationText = "Regard loin avant de tourner."
        model.persistLocalDraft()
        await server.setReceiptAvailable(false)
        #expect(!(await model.saveDraft()))
        #expect(drafts.values[Self.draftID] != nil && !model.reportSaveConfirmed)
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        #expect(model.reportSaveConfirmed && drafts.values.isEmpty)
    }

    @Test func withoutAVaultTheEntryStaysInMemoryAndTheReportStillSaves() async {
        let drafts = LocalDraftStub(); drafts.fails = true
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        model.nextStep = "À garder en mémoire"
        model.persistLocalDraft()
        #expect(drafts.values.isEmpty && model.nextStep == "À garder en mémoire" && model.errorMessage == nil)
        #expect(await model.saveDraft())
        #expect(model.reportSaveConfirmed)
    }

    @Test func givingUpTheEntryRemovesItFromTheDevice() async {
        let drafts = LocalDraftStub()
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub(), drafts: drafts)
        await model.load()
        model.workedOn = "Brouillon abandonné"
        model.persistLocalDraft()
        #expect(drafts.values.count == 1)
        model.discardLocalDraft()
        #expect(drafts.values.isEmpty)
    }

    // MARK: Données de test

    private func workspace(_ server: LessonFinishServer, outbox: ConfigurationOutboxStub, drafts: LocalDraftStub) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: outbox, localDrafts: drafts)
    }

    private static func localDraft(base: String = "", edited: String) -> SchoolReportLocalDraft {
        SchoolReportLocalDraft(draftID: draftID, lessonID: HubFixture.lessonID,
            base: .init(workedOn: base, observationText: "", nextStep: "", observations: []),
            edited: .init(workedOn: edited, observationText: "", nextStep: "", observations: []),
            savedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    private static func competency(_ order: Int) -> SchoolCatalogCompetency {
        SchoolCatalogCompetency(id: UUID(), schoolId: HubFixture.schoolID, version: 1, curriculumVersionId: UUID(),
            key: "c\(order)", label: "Compétence \(order)", description: "", sortOrder: order)
    }

    private static func observation(competency: UUID, status: String) -> SchoolObservation {
        SchoolObservation(id: UUID(), schoolId: HubFixture.schoolID, version: 1, lessonId: HubFixture.lessonID,
            trainingId: HubFixture.trainingID, draftId: nil, captureId: nil, segmentId: nil, pointSequence: nil,
            competencyId: competency, text: "Signalement", origin: "LIVE", observedAt: "2026-09-28T12:10:00Z",
            eventKind: "QUALIFIED", eventStatus: status, authorMembershipId: ConfigurationFixture.membershipID)
    }
}

/// Ce qu’une leçon contient, et les étapes attendues.
struct SchoolReportStepCase: Sendable {
    let hasTrip: Bool
    let observations: Int
    let competencies: Int
    let expected: [SchoolReportStep]
}

/// Coffre de test en mémoire ; `fails` reproduit un trousseau illisible.
@MainActor
final class LocalDraftStub: SchoolReportLocalDraftStore {
    var values: [UUID: SchoolReportLocalDraft] = [:]
    var fails = false

    func read(scope: SchoolCommandScope, draftID: UUID) throws -> SchoolReportLocalDraft? {
        if fails { throw SchoolConfigurationFailure.storage }
        return values[draftID]
    }
    func save(_ draft: SchoolReportLocalDraft, scope: SchoolCommandScope) throws {
        if fails { throw SchoolConfigurationFailure.storage }
        values[draft.draftID] = draft
    }
    func remove(scope: SchoolCommandScope, draftID: UUID) throws {
        if fails { throw SchoolConfigurationFailure.storage }
        values[draftID] = nil
    }
}
