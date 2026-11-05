import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolOnboardingExitTests {
    private func member(_ scope: SchoolCommandScope) -> SchoolMembership {
        .init(membershipId: scope.membershipID, schoolId: scope.schoolID, schoolName: "École test",
              roles: ["LEARNER"], grants: [], accessEpoch: scope.accessEpoch)
    }
    private func person(_ scopes: [SchoolCommandScope]) -> SchoolPerson {
        .init(personId: scopes[0].personID, version: 1, displayName: "Test", locale: "fr", memberships: scopes.map(member))
    }
    private func draft() -> SchoolOnboardingDraft {
        .init(onboardingID: ProfileFixture.onboardingID, version: 1, base: .init(), edited: .init(), step: .identity, savedAt: Date())
    }

    // Missing Root orchestration used to leave the closed sheet's encrypted file behind.
    @Test func closedSheetPurgesAllKnownMembershipKindsButPreservesOtherScopes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        let second = SchoolCommandScope(personID: scope.personID, schoolID: UUID(), membershipID: UUID(), accessEpoch: 3, apiBaseURL: scope.apiBaseURL)
        let others = [ConfigurationFixture.scope(epoch: 9),
            SchoolCommandScope(personID: UUID(), schoolID: scope.schoolID, membershipID: scope.membershipID, accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL),
            SchoolCommandScope(personID: scope.personID, schoolID: scope.schoolID, membershipID: scope.membershipID, accessEpoch: scope.accessEpoch, apiBaseURL: "https://other.invalid")]
        for target in [scope, second] + others {
            for kind in [SchoolOnboardingKind.student, .staff] { try store.save(draft(), scope: target, kind: kind) }
        }
        let exit = SchoolOnboardingExitModel(store: store)
        var masked = false
        let ticket = exit.begin(person: person([scope, second, scope]), apiBaseURL: scope.apiBaseURL, liveWorkspace: nil, mask: { masked = true })
        #expect(masked)
        var order: [String] = []
        await exit.finish(ticket, revokePush: { order.append("push") }, closeIdentity: { order.append("identity") })
        #expect(order == ["push", "identity"])
        #expect(exit.errorMessage == nil)
        for target in [scope, second] {
            #expect(try store.read(scope: target, kind: .student) == nil)
            #expect(try store.read(scope: target, kind: .staff) == nil)
        }
        for target in others { #expect(try store.read(scope: target, kind: .student) != nil) }
        exit.retry()
        #expect(exit.errorMessage == nil)
    }

    @Test func failureStillMasksAndClosesThenRetriesOnlyFailedScopes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        try real.save(draft(), scope: scope, kind: .student)
        // Illisible : le réessai doit supprimer sans déchiffrer, et un refus reste un échec.
        let unreadable = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data([0, 1, 2]).write(to: unreadable)
        try real.save(draft(), scope: scope, kind: .staff)
        let store = ExitFailingStore(real: real)
        let exit = SchoolOnboardingExitModel(store: store)
        var masked = false, closed = false
        let ticket = exit.begin(person: person([scope]), apiBaseURL: scope.apiBaseURL, liveWorkspace: nil, mask: { masked = true })
        await exit.finish(ticket, revokePush: {}, closeIdentity: { closed = true })
        #expect(masked && closed && exit.errorMessage != nil)
        #expect(try real.read(scope: scope, kind: .staff) == nil)
        #expect(FileManager.default.fileExists(atPath: unreadable.path))
        store.fail = false
        exit.retry()
        #expect(exit.errorMessage == nil)
        #expect(try real.read(scope: scope, kind: .student) == nil)
        exit.retry()
        #expect(exit.errorMessage == nil)
    }

    @Test(arguments: [false, true])
    func lateConfirmationOrItsReloadCannotEraseNewSessionDraft(duringSend: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        let api = ProfileAPIStub()
        api.onboardingValue = ProfileFixture.onboarding(step: .review)
        let workspace = SchoolProfileWorkspace(scope: scope, roles: ["LEARNER"], learnerID: ProfileFixture.learnerID,
            isOwnProfile: true, onboardingKind: .student, api: api, outbox: ConfigurationOutboxStub(), onboardingDraftStore: store, onboardingDraftDelay: .zero)
        await workspace.load()
        workspace.draft.contactPhone = "012345"
        let exit = SchoolOnboardingExitModel(store: store)
        let replacement = draft()
        var ticket: UUID?
        var storageFailure = false
        let leave = {
            ticket = exit.begin(person: person([scope]), apiBaseURL: scope.apiBaseURL, liveWorkspace: workspace, mask: {})
            exit.connectionStarted()
            do { try store.save(replacement, scope: scope, kind: .student) } catch { storageFailure = true }
        }
        if duringSend { api.onSend = leave }
        else { api.schoolHandler = { leave(); return ConfigurationFixture.school(status: "ACTIVE") } }
        _ = await workspace.completeOnboardingAfterConfirmation()
        #expect(ticket != nil && !storageFailure)
        #expect(workspace.invalidated && workspace.profile == nil)
        #expect(try store.read(scope: scope, kind: .student) == replacement)
    }

    @Test func lateInitialReadDoesNotRestoreDraftAndLiveScopeIsIncluded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        let api = ProfileAPIStub()
        let workspace = SchoolProfileWorkspace(scope: scope, roles: ["LEARNER"], learnerID: ProfileFixture.learnerID,
            isOwnProfile: true, onboardingKind: .student, api: api, outbox: ConfigurationOutboxStub(), onboardingDraftStore: store)
        try store.save(draft(), scope: scope, kind: .student)
        let exit = SchoolOnboardingExitModel(store: store)
        // L'adhésion vivante est absente de la nouvelle liste, mais appartient encore à ce compte/API.
        let account = SchoolPerson(personId: scope.personID, version: 1, displayName: "Test", locale: "fr", memberships: [])
        api.schoolHandler = {
            _ = exit.begin(person: account, apiBaseURL: scope.apiBaseURL, liveWorkspace: workspace, mask: {})
            return ConfigurationFixture.school(status: "ACTIVE")
        }
        await workspace.load()
        #expect(workspace.invalidated && workspace.profile == nil && workspace.onboarding == nil)
        #expect(try store.read(scope: scope, kind: .student) == nil)
    }

    @Test func newConnectionFencesOldIdentityCallbackAndRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        let store = ExitFailingStore(real: real)
        let exit = SchoolOnboardingExitModel(store: store)
        let ticket = exit.begin(person: person([scope]), apiBaseURL: scope.apiBaseURL, liveWorkspace: nil, mask: {})
        var closed = false
        await exit.finish(ticket, revokePush: {
            exit.connectionStarted()
            try? real.save(draft(), scope: scope, kind: .student)
        }, closeIdentity: { closed = true })
        store.fail = false
        exit.retry()
        #expect(!closed && exit.errorMessage == nil)
        #expect(try real.read(scope: scope, kind: .student) != nil)
    }

    @Test func ordinaryDismissalKeepsDraftButLogoutCancelsDeferredSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let scope = ConfigurationFixture.scope()
        let api = ProfileAPIStub()
        let workspace = SchoolProfileWorkspace(scope: scope, roles: ["LEARNER"], learnerID: ProfileFixture.learnerID,
            isOwnProfile: true, onboardingKind: .student, api: api, outbox: ConfigurationOutboxStub(),
            onboardingDraftStore: store, onboardingDraftDelay: .milliseconds(30))
        try store.save(draft(), scope: scope, kind: .student)
        await workspace.load()
        workspace.draft.contactPhone = "012345"
        let exit = SchoolOnboardingExitModel(store: store)
        let ticket = exit.begin(person: person([scope]), apiBaseURL: scope.apiBaseURL, liveWorkspace: workspace, mask: {})
        await exit.finish(ticket, revokePush: {}, closeIdentity: {})
        try await Task.sleep(for: .milliseconds(100))
        #expect(workspace.invalidated)
        #expect(try store.read(scope: scope, kind: .student) == nil)
        let reopened = SchoolProfileWorkspace(scope: scope, roles: ["LEARNER"], learnerID: ProfileFixture.learnerID,
            isOwnProfile: true, onboardingKind: .student, api: api, outbox: ConfigurationOutboxStub(), onboardingDraftStore: store, onboardingDraftDelay: .zero)
        await reopened.load()
        #expect(reopened.draft.contactPhone != "012345")
        reopened.draft.contactPhone = "065432"
        reopened.invalidate()
        #expect(try store.read(scope: scope, kind: .student) != nil)
    }
}

@MainActor private final class ExitFailingStore: SchoolOnboardingDraftStore {
    let real: any SchoolOnboardingDraftStore
    var fail = true
    init(real: any SchoolOnboardingDraftStore) { self.real = real }
    func read(scope: SchoolCommandScope, kind: SchoolOnboardingKind) throws -> SchoolOnboardingDraft? { try real.read(scope: scope, kind: kind) }
    func save(_ value: SchoolOnboardingDraft, scope: SchoolCommandScope, kind: SchoolOnboardingKind) throws { try real.save(value, scope: scope, kind: kind) }
    func remove(scope: SchoolCommandScope, kind: SchoolOnboardingKind, discardingUnreadable: Bool) throws {
        if fail && kind == .student { throw SchoolConfigurationFailure.storage }
        try real.remove(scope: scope, kind: kind, discardingUnreadable: discardingUnreadable)
    }
}
