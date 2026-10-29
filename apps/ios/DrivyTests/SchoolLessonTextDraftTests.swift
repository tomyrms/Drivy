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

    private func workspace(_ server: HubServer, store: any SchoolLessonTextDraftStore) -> SchoolLessonReportWorkspace {
        let member = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École synthétique", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: "https://api.example.invalid")!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: member, lessonID: HubFixture.lessonID,
            client: client, outbox: ConfigurationOutboxStub(), textDrafts: store)
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
