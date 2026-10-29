import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolSelfProfileIntentTests {
    private let baseURL = URL(string: "https://profile.example.invalid")!

    @Test func validatedFieldsAreSharedAndRestoredWithoutBecomingConfirmed() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        let workspace = await make(api, store)
        let editor = SchoolSelfProfileEditor(workspace: workspace)
        await editor.load()
        editor.edit.displayName = "Nom local"
        editor.edit.contactEmail = "contact@example.invalid"
        api.holdsWrites = true
        let send = Task { await editor.save() }
        await eventually { api.releaseWrite != nil }
        #expect(workspace.person?.displayName == "Nom local")
        #expect(workspace.person?.version == 1)
        #expect(workspace.selfProfile?.contactEmail == "contact@example.invalid")
        #expect(workspace.confirmedSelfProfile?.displayName == "Compte test")
        #expect(workspace.hasPendingSelfProfile)
        #expect(store.values.values.first?.attempted?.base.version == 1)

        // Une saisie après le premier départ ne doit pas être remplacée par son ACK.
        editor.edit.displayName = "Saisie suivante"
        api.finishWrite()
        #expect(await send.value)
        #expect(editor.trimmed.displayName == "Saisie suivante")
        #expect(editor.hasEdits)
        #expect(!workspace.hasPendingSelfProfile)

        var next = SchoolSelfProfileEdit(api.profile); next.displayName = "Conservé"
        _ = try workspace.retainSelfProfile(next)
        let reopened = await make(api, store)
        let restored = SchoolSelfProfileEditor(workspace: reopened)
        await restored.load()
        #expect(restored.trimmed.displayName == "Conservé")
        #expect(restored.loaded?.displayName == "Nom local")
        #expect(restored.errorMessage != nil && restored.canSave)
        #expect(api.writes.count == 1)
    }

    @Test func fieldWritePhotoThenRemovalShareVersionsAndOldAckCannotRestorePhoto() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        let workspace = await make(api, store)
        let editor = SchoolSelfProfileEditor(workspace: workspace)
        await editor.load()
        editor.edit.displayName = "Nouveau nom"
        api.holdsWrites = true
        let send = Task { await editor.save() }
        await eventually { api.releaseWrite != nil }
        editor.choosePhoto(Data([1, 2, 3]))
        editor.choosePhoto(nil)
        #expect(workspace.photo(for: api.profile.personId) == nil)
        #expect(workspace.pendingSelfPhotoChoice == .remove)
        #expect(api.writes.map(\.kind) == [.fields])
        api.finishWrite()
        #expect(await send.value)
        await eventually { editor.photoIntent == nil }
        #expect(api.writes.map(\.kind) == [.fields, .photo])
        #expect(api.writes.map(\.version) == [1, 2])
        #expect(api.writes.last?.jpeg == nil)
        #expect(workspace.selfPhoto == nil && !workspace.hasPendingSelfProfile)
        #expect(editor.photoResult == "Photo retirée.")
    }

    @Test func lostReplyIsReadBeforeRetryAndFailedGetDoesNotSendAgain() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        let workspace = await make(api, store)
        let editor = SchoolSelfProfileEditor(workspace: workspace)
        await editor.load()
        editor.edit.displayName = "Écrit avant coupure"
        api.loseNextReply = true
        #expect(!(await editor.save()))
        #expect(api.profile.displayName == "Écrit avant coupure")
        #expect(workspace.hasPendingSelfProfile && editor.errorMessage != nil)
        api.failReads = true
        #expect(!(await editor.save()))
        #expect(api.writes.count == 1)

        api.failReads = false
        let reopened = await make(api, store)
        let restored = SchoolSelfProfileEditor(workspace: reopened)
        await restored.load()
        // Même si la valeur lue est déjà la bonne, la reprise reste actionnable jusqu'à réconciliation du journal.
        #expect(restored.hasEdits && restored.canSave)
        #expect(await restored.save())
        #expect(api.writes.count == 1)
        #expect(!reopened.hasPendingSelfProfile)
        #expect(store.values.values.allSatisfy(\.isEmpty))
    }

    @Test func conflictRetainsChoiceAndRequiresExplicitReviewBeforeNewVersion() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        let workspace = await make(api, store)
        var desired = SchoolSelfProfileEdit(api.profile); desired.displayName = "Mon choix"
        let id = try workspace.retainSelfProfile(desired)
        api.profile = SchoolSelfProfile(personId: api.profile.personId, displayName: "Autre appareil", version: 2)
        do { _ = try await workspace.sendSelfProfileIntent(id); Issue.record("Le conflit devait être signalé") }
        catch { #expect(error as? SchoolSelfProfileFailure == .changed) }
        #expect(workspace.confirmedSelfProfile?.displayName == "Autre appareil")
        #expect(workspace.person?.displayName == "Mon choix")
        #expect(store.values.values.first?.attempted == nil)
        #expect(workspace.hasPendingSelfProfile)

        let editor = SchoolSelfProfileEditor(workspace: workspace)
        await editor.load()
        #expect(editor.loaded?.displayName == "Autre appareil")
        #expect(editor.trimmed.displayName == "Mon choix")
        #expect(await editor.save())
        #expect(api.writes.map(\.version) == [1, 2])
        #expect(api.profile.displayName == "Mon choix" && api.profile.version == 3)
    }

    @Test func storageFailureNeverStartsANewWriteOrClaimsLocalConfirmation() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        let workspace = await make(api, store)
        let editor = SchoolSelfProfileEditor(workspace: workspace)
        await editor.load()
        editor.edit.displayName = "À garder"
        store.failWrites = true
        #expect(!(await editor.save()))
        #expect(api.writes.isEmpty && !workspace.hasPendingSelfProfile)
        #expect(editor.trimmed.displayName == "À garder")
        store.failWrites = false
        api.afterCommit = { store.failWrites = true }
        #expect(!(await editor.save()))
        #expect(api.profile.displayName == "À garder")
        #expect(workspace.hasPendingSelfProfile)
        #expect(store.values.values.first?.attempted != nil)
        #expect(editor.errorMessage != nil)
        store.failWrites = false; api.afterCommit = nil
        #expect(await editor.save())
        #expect(api.writes.count == 1)

        store.failReads = true
        let unreadable = await make(api, store, readsProfile: false)
        #expect(throws: SchoolConfigurationFailure.storage) { try unreadable.retainSelfPhoto(Data([1])) }
        #expect(unreadable.selfProfileIntentError != nil)
        #expect(api.writes.count == 1)
    }

    @Test func latePhotoAckAndOldEditorCannotAffectAnotherAccount() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        let workspace = await make(api, store)
        let editor = SchoolSelfProfileEditor(workspace: workspace)
        await editor.load()
        api.holdsWrites = true
        editor.choosePhoto(Data([7, 8]))
        await eventually { api.releaseWrite != nil }
        let oldPerson = api.profile.personId
        workspace.reset()
        api.profile = SchoolSelfProfile(personId: UUID(), displayName: "Autre compte", version: 1)
        api.photo = nil
        await workspace.loadAccount()
        api.finishWrite()
        await eventually { editor.photoIntent == nil }
        #expect(workspace.person?.displayName == "Autre compte")
        #expect(workspace.selfPhoto == nil && workspace.pendingSelfPhotoChoice == nil)
        #expect(editor.displayedPhoto(confirmed: Data([9])) == nil)
        editor.choosePhoto(Data([9]))
        #expect(api.writes.count == 1)
        #expect(store.values.keys.contains { $0.personID == oldPerson })
    }

    @Test func failedEditorReadKeepsKnownFullProfileInsteadOfClearingContacts() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        api.profile = SchoolSelfProfile(personId: api.profile.personId, displayName: "Compte test",
            firstName: "Prénom", lastName: "Nom", contactPhone: "+41 22 000 00 00",
            contactEmail: "contact@example.invalid", birthDate: "2000-01-01", version: 1)
        let workspace = await make(api, store)
        let editor = SchoolSelfProfileEditor(workspace: workspace)
        api.failReads = true
        await editor.load()
        #expect(editor.trimmed.contactEmail == "contact@example.invalid")
        #expect(editor.trimmed.firstName == "Prénom")
        editor.edit.displayName = "Nom corrigé"
        api.failReads = false
        #expect(await editor.save())
        #expect(api.profile.contactEmail == "contact@example.invalid")
        #expect(api.profile.birthDate == "2000-01-01")
        #expect(api.profile.firstName == "Prénom")
    }

    @Test func failedPersistenceOfNewRemovalKeepsItsPreviewAfterOlderPhotoAck() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        let workspace = await make(api, store)
        let editor = SchoolSelfProfileEditor(workspace: workspace)
        await editor.load()
        api.holdsWrites = true
        let photo = Data([3, 2, 1])
        editor.choosePhoto(photo)
        await eventually { api.releaseWrite != nil }
        store.failWrites = true
        editor.choosePhoto(nil)
        #expect(editor.displayedPhoto(confirmed: photo) == nil)
        #expect(editor.hasUnretainedPhoto && editor.failedPhoto == .remove)
        #expect(editor.photoIntent == nil && editor.photoErrorMessage != nil)
        #expect(workspace.photo(for: api.profile.personId) == photo)
        store.failWrites = false
        api.finishWrite()
        await eventually { !editor.isSavingPhoto }
        #expect(editor.displayedPhoto(confirmed: workspace.selfPhoto?.data) == nil)
        #expect(editor.hasUnretainedPhoto && editor.photoErrorMessage != nil)
        #expect(editor.photoResult == nil)
        #expect(api.writes.count == 1)
    }

    @Test func newerAccountReadDoesNotLetOldFullProfileReplaceFreshDossier() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        api.memberships = [SchoolMembership(membershipId: UUID(), schoolId: UUID(), schoolName: "École test",
            roles: ["LEARNER"], grants: [], accessEpoch: 1)]
        let workspace = await make(api, store)
        #expect(workspace.learners.first?.displayName == "Compte test")
        api.profile = SchoolSelfProfile(personId: api.profile.personId, displayName: "Nom actualisé ailleurs",
            contactEmail: "nouveau@example.invalid", version: 2)
        #expect(await workspace.refreshAccount(minimumInterval: 0))
        await workspace.refreshLearners(minimumInterval: 0)
        #expect(workspace.confirmedSelfProfile?.version == 1)
        #expect(workspace.person?.displayName == "Nom actualisé ailleurs")
        #expect(workspace.learners.first?.displayName == "Nom actualisé ailleurs")
        #expect(workspace.learners.first?.contactEmail == "nouveau@example.invalid")
        #expect(workspace.ownLearner?.displayName == "Nom actualisé ailleurs")
    }

    @Test func encryptedJournalKeepsLatestAndAttemptSeparateAndIsolated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProfileIntent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 0x48, count: 32)
        let store = EncryptedSchoolSelfProfileIntentStore(directory: directory, keyData: key)
        let profile = SchoolSelfProfile(personId: UUID(), displayName: "Profil confidentiel", version: 3)
        let scope = AccountIntentScope(personID: profile.personId, apiBaseURL: baseURL.absoluteString)
        let attempt = SchoolSelfProfileIntent(id: UUID(), kind: .photo, base: profile, fields: nil,
            jpeg: Data(repeating: 0xAB, count: 262_144))
        let latest = SchoolSelfProfileIntent(id: UUID(), kind: .photo, base: profile, fields: nil,
            jpeg: Data(repeating: 0xCD, count: 262_144))
        let value = SchoolSelfProfileIntents(photo: latest, attempted: attempt)
        try store.save(value, scope: scope)
        #expect(try store.read(scope: scope) == value)
        #expect(try store.read(scope: .init(personID: UUID(), apiBaseURL: scope.apiBaseURL)) == nil)
        #expect(try store.read(scope: .init(personID: scope.personID, apiBaseURL: "https://other.example.invalid")) == nil)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let before = try Data(contentsOf: file)
        #expect(before.range(of: Data("Profil confidentiel".utf8)) == nil)
        let wrong = EncryptedSchoolSelfProfileIntentStore(directory: directory, keyData: Data(repeating: 0x49, count: 32))
        #expect(throws: SchoolConfigurationFailure.storage) { try wrong.save(.init(), scope: scope) }
        #expect(try Data(contentsOf: file) == before)
        try store.save(.init(), scope: scope)
        #expect(try store.read(scope: scope) == nil)
    }

    private func make(_ api: SelfIntentAPI, _ store: SelfIntentMemoryStore,
                      readsProfile: Bool = true) async -> SchoolWorkspace {
        let workspace = SchoolWorkspace(api: api, accountIntentBaseURL: baseURL, selfIntentStore: store)
        await workspace.loadAccount()
        if readsProfile { _ = try? await workspace.loadSelfProfile() }
        return workspace
    }

    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

@MainActor private final class SelfIntentMemoryStore: SchoolSelfProfileIntentStore {
    var values: [AccountIntentScope: SchoolSelfProfileIntents] = [:]
    var failReads = false
    var failWrites = false
    func read(scope: AccountIntentScope) throws -> SchoolSelfProfileIntents? {
        if failReads { throw SchoolConfigurationFailure.storage }
        return values[scope]
    }
    func save(_ value: SchoolSelfProfileIntents, scope: AccountIntentScope) throws {
        if failWrites { throw SchoolConfigurationFailure.storage }
        values[scope] = value
    }
}

@MainActor private final class SelfIntentAPI: SchoolAPI {
    struct Write { let kind: SchoolSelfProfileIntent.Kind; let version: Int; let jpeg: Data? }
    var profile = SchoolSelfProfile(personId: UUID(), displayName: "Compte test", version: 1)
    var photo: Data?
    var memberships: [SchoolMembership] = []
    let learnerID = UUID()
    var writes: [Write] = []
    var failReads = false
    var loseNextReply = false
    var holdsWrites = false
    var releaseWrite: CheckedContinuation<Void, Never>?
    var afterCommit: (() -> Void)?

    func me() async throws -> SchoolPerson {
        SchoolPerson(personId: profile.personId, version: profile.version, displayName: profile.displayName,
            locale: "fr", memberships: memberships)
    }
    func selfProfile() async throws -> SchoolSelfProfile {
        if failReads { throw SchoolAPIError.unavailable }
        return profile
    }
    func personPhoto(personID: UUID) async throws -> Data? { photo }
    func saveSelfProfile(_ edit: SchoolSelfProfileEdit, version: Int) async throws -> SchoolSelfProfile {
        writes.append(Write(kind: .fields, version: version, jpeg: nil))
        guard version == profile.version else { throw SchoolSelfProfileFailure.changed }
        let base = SchoolSelfProfile(personId: profile.personId, displayName: profile.displayName,
            photoVersion: profile.photoVersion, version: version + 1)
        profile = SchoolSelfProfileIntent.projecting(edit, on: base)
        return try await committed(profile)
    }
    func setSelfPhoto(_ jpeg: Data?, version: Int) async throws -> SchoolSelfProfile {
        writes.append(Write(kind: .photo, version: version, jpeg: jpeg))
        guard version == profile.version else { throw SchoolSelfProfileFailure.changed }
        let edit = SchoolSelfProfileEdit(profile)
        let base = SchoolSelfProfile(personId: profile.personId, displayName: profile.displayName,
            photoVersion: jpeg == nil ? nil : (profile.photoVersion ?? 0) + 1, version: version + 1)
        profile = SchoolSelfProfileIntent.projecting(edit, on: base); photo = jpeg
        return try await committed(profile)
    }
    private func committed(_ result: SchoolSelfProfile) async throws -> SchoolSelfProfile {
        if holdsWrites { await withCheckedContinuation { releaseWrite = $0 } }
        afterCommit?()
        if loseNextReply { loseNextReply = false; throw SchoolAPIError.unavailable }
        return result
    }
    func finishWrite() { holdsWrites = false; let saved = releaseWrite; releaseWrite = nil; saved?.resume() }
    func school(id: UUID) async throws -> SchoolDetails {
        SchoolDetails(id: id, schoolId: id, version: 1, name: "École test", timeZone: "Europe/Zurich", status: "ACTIVE",
            contactEmail: "ecole@example.invalid", contactPhone: nil, logoAssetId: nil,
            modules: SchoolModules(gpsEnabled: true, packsEnabled: false, collectiveCoursesEnabled: false,
                courseOffersVisibleByDefault: false), configurationVersion: 1)
    }
    func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> {
        .init(items: [SchoolLearner(id: learnerID, schoolId: schoolID, personId: profile.personId, version: 1,
            displayName: profile.displayName, contactEmail: profile.contactEmail, contactPhone: profile.contactPhone,
            archivedAt: nil, profileReadiness: nil, profilePhotoDocumentId: nil)], nextCursor: nil)
    }
    func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner { throw SchoolAPIError.notFound }
    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining> { .init(items: [], nextCursor: nil) }
    func training(schoolID: UUID, id: UUID) async throws -> SchoolTraining { throw SchoolAPIError.notFound }
}
