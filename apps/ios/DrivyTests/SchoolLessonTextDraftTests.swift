import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolLessonTextDraftTests {
    @Test func preparationSurvivesClosingWithoutSendingIt() async throws {
        let server = HubServer(), store = TextDraftMemoryStore()
        let first = workspace(server, store: store)
        await first.load(); first.administrativeNote = "Note privée synthétique"
        #expect(first.canKeepLocalDraft && first.keepLocalDraftAndClose())
        let reopened = workspace(server, store: store)
        await reopened.load()
        #expect(reopened.administrativeNote == "Note privée synthétique" && reopened.preparationChanged)
        #expect(!reopened.needsReload && reopened.canMutate)
        #expect(await server.requests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func changedServerBaseDoesNotSilentlyAcceptARestoredPreparation() async throws {
        let server = HubServer(), store = TextDraftMemoryStore()
        let first = workspace(server, store: store)
        await first.load(); first.administrativeNote = "Saisie locale"
        #expect(first.keepLocalDraftAndClose())
        await server.setPreparation(note: "Autre appareil", version: 2)
        let reopened = workspace(server, store: store)
        await reopened.load()
        #expect(reopened.administrativeNote == "Saisie locale" && reopened.needsReload && !reopened.canMutate)
        #expect(reopened.persistLocalDraft())
        let again = workspace(server, store: store)
        await again.load()
        #expect(again.needsReload && again.administrativeNote == "Saisie locale")
        await again.load(discardingEdits: true)
        #expect(again.administrativeNote == "Autre appareil" && !again.preparationChanged)
    }

    @Test func anAcknowledgedOlderRevisionKeepsTheNewerDraftWithoutFalseConflict() {
        let sent = SchoolLessonTextDraft.Content(text: "Envoyé"), edited = SchoolLessonTextDraft.Content(text: "Suite locale")
        let value = SchoolLessonTextDraft(kind: .wish, resourceID: HubFixture.trainingID, baseVersion: 1,
            base: .init(), edited: edited, sent: sent, savedAt: Date())
        #expect(!value.conflicts(with: sent))
        #expect(value.conflicts(with: .init(text: "Autre appareil")))
    }

    @Test func storageFailureBlocksAFalseKeptDraftAndAnUnreadableFileIsNotOverwritten() async {
        let server = HubServer(), store = TextDraftMemoryStore()
        let model = workspace(server, store: store)
        await model.load(); model.administrativeNote = "À garder"
        store.failWrites = true
        #expect(!model.keepLocalDraftAndClose() && !model.isInvalidated && model.localDraftError != nil)
        store.failWrites = false; store.failReads = true
        let reopened = workspace(server, store: store)
        await reopened.load()
        #expect(reopened.localDraftReadFailed && !reopened.acceptsInput && !reopened.canMutate)
        #expect(!reopened.persistLocalDraft())
    }

    @Test func verifyingAReportReceiptKeepsTheIndependentPreparationDraft() async throws {
        let server = LessonFinishServer(), store = TextDraftMemoryStore(), reports = LocalDraftStub()
        let model = workspace(server, store: store, reports: reports)
        await model.load()
        model.administrativeNote = "Préparation privée à garder"
        model.workedOn = "Bilan envoyé"
        #expect(model.persistLocalDraft())
        await server.setReceiptAvailable(false)
        #expect(await model.saveDraft() == false)
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        #expect(model.reportSaveConfirmed && reports.values.isEmpty)
        let retained = try #require(try store.read(scope: ConfigurationFixture.scope(), kind: .preparation, resourceID: HubFixture.lessonID))
        #expect(retained.edited.text == "Préparation privée à garder")
        model.close()
        let reopened = workspace(server, store: store, reports: reports)
        await reopened.load()
        #expect(reopened.administrativeNote == retained.edited.text && reopened.preparationChanged)
    }

    @Test func verifyingAReportReceiptUsesTheDurableBodyAfterTheFirstSendFinished() async throws {
        let server = LessonFinishServer(), store = TextDraftMemoryStore(), reports = LocalDraftStub()
        let model = workspace(server, store: store, reports: reports)
        await server.storeSaves(); await server.holdSave(); await server.setReceiptAvailable(false)
        await model.load(); model.workedOn = "Bilan envoyé"
        let sending = Task { await model.saveDraft() }
        try await HubFixture.wait { await server.isHoldingSave() }
        model.workedOn = "Suite du bilan à conserver"
        #expect(model.persistLocalDraft())
        await server.releaseSave()
        #expect(await sending.value == false)
        // saveDraft est terminé : il n’existe plus de variable éphémère du premier envoi.
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        #expect(model.pending == nil && !model.reportSaveConfirmed)
        #expect(model.workedOn == "Suite du bilan à conserver" && model.draft?.workedOn == "Bilan envoyé")
        #expect(model.reportEdited && !model.needsReload && model.canMutate)
        let retained = try #require(reports.values.values.first)
        #expect(retained.base.workedOn == "Bilan envoyé" && retained.edited.workedOn == model.workedOn)
    }

    @Test func anotherLessonsPendingPreparationIsNotTheSentBaseOfThisDraft() async throws {
        let server = HubServer(), store = TextDraftMemoryStore(), outbox = ConfigurationOutboxStub()
        let operation = UUID()
        try outbox.save(.init(id: operation, scope: ConfigurationFixture.scope(), kind: .savePreparation,
            resourceVersion: 1, createdAt: Date(),
            body: JSONEncoder().encode(SchoolSavePreparation(operationId: operation, goals: [], administrativeCheckNote: "Autre leçon")),
            resourceID: UUID(), routeResourceID: UUID()))
        let model = workspace(server, store: store, outbox: outbox)
        await model.load(); model.administrativeNote = "Saisie de cette leçon"
        #expect(model.persistLocalDraft())
        let retained = try #require(try store.read(scope: ConfigurationFixture.scope(), kind: .preparation, resourceID: HubFixture.lessonID))
        #expect(retained.sent == nil && retained.edited.text == "Saisie de cette leçon")
    }

    @Test func encryptedTextsAreSeparatedByKindTrainingLessonAccountAndEpoch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolLessonTextDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        let value = SchoolLessonTextDraft(kind: .wish, resourceID: HubFixture.trainingID, baseVersion: 3,
            base: .init(), edited: .init(text: "Souhait synthétique confidentiel"), sent: nil, savedAt: Date())
        try store.save(value, scope: scope)
        #expect(try store.read(scope: scope, kind: .wish, resourceID: HubFixture.trainingID) == value)
        #expect(try store.read(scope: scope, kind: .preparation, resourceID: HubFixture.trainingID) == nil)
        #expect(try store.read(scope: scope, kind: .wish, resourceID: HubFixture.lessonID) == nil)
        let changed = SchoolCommandScope(personID: scope.personID, schoolID: scope.schoolID, membershipID: scope.membershipID,
            accessEpoch: scope.accessEpoch + 1, apiBaseURL: scope.apiBaseURL)
        #expect(try store.read(scope: changed, kind: .wish, resourceID: HubFixture.trainingID) == nil)
        let other = SchoolCommandScope(personID: UUID(), schoolID: scope.schoolID, membershipID: scope.membershipID,
            accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL)
        #expect(try store.read(scope: other, kind: .wish, resourceID: HubFixture.trainingID) == nil)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(try files.allSatisfy { !(String(data: try Data(contentsOf: $0), encoding: .utf8) ?? "").contains(value.edited.text) })
        try store.remove(scope: scope, kind: .wish, resourceID: HubFixture.trainingID, explicit: false)
        #expect(try store.read(scope: scope, kind: .wish, resourceID: HubFixture.trainingID) == nil)
    }

    private func workspace(_ server: any SchoolHTTPTransport, store: any SchoolLessonTextDraftStore,
                           reports: (any SchoolReportLocalDraftStore)? = nil,
                           outbox: any SchoolCommandOutbox = ConfigurationOutboxStub()) -> SchoolLessonReportWorkspace {
        let member = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École synthétique", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: "https://api.example.invalid")!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: member, lessonID: HubFixture.lessonID,
            client: client, outbox: outbox, localDrafts: reports, textDrafts: store)
    }
}

@MainActor private final class TextDraftMemoryStore: SchoolLessonTextDraftStore {
    var values: [String: SchoolLessonTextDraft] = [:]
    var failReads = false, failWrites = false
    private func key(_ kind: SchoolLessonTextDraft.Kind, _ id: UUID) -> String { "\(kind.rawValue):\(id)" }
    func read(scope: SchoolCommandScope, kind: SchoolLessonTextDraft.Kind, resourceID: UUID) throws -> SchoolLessonTextDraft? {
        if failReads { throw SchoolConfigurationFailure.storage }
        return values[key(kind, resourceID)]
    }
    func save(_ value: SchoolLessonTextDraft, scope: SchoolCommandScope) throws {
        if failWrites { throw SchoolConfigurationFailure.storage }
        values[key(value.kind, value.resourceID)] = value
    }
    func remove(scope: SchoolCommandScope, kind: SchoolLessonTextDraft.Kind, resourceID: UUID, explicit: Bool) throws {
        if failWrites || (failReads && !explicit) { throw SchoolConfigurationFailure.storage }
        values[key(kind, resourceID)] = nil
    }
}
