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
        let noRetainedIntent = store.values.values.allSatisfy { $0.isEmpty }
        #expect(noRetainedIntent)
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

    // MARK: Génération de photo (#450)

    private func startWithPhoto(_ api: SelfIntentAPI, bytes: Data, generation: Int? = 1) {
        api.profile = SchoolSelfProfile(personId: api.profile.personId, displayName: "Compte test",
            photoVersion: 1, photoGeneration: generation, version: 1)
        api.photo = bytes
    }

    @Test func aPhotoRemovedThenReplacedElsewhereIsReloadedEvenWhenItsVersionComesBack() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        startWithPhoto(api, bytes: Data([1]))
        let workspace = await make(api, store)
        #expect(workspace.selfPhoto?.data == Data([1]) && workspace.selfPhoto?.generation == 1)

        // Autre appareil : retrait puis remplacement. Celui-ci ne voit jamais l'état « sans photo ».
        api.changePhotoElsewhere(nil)
        api.changePhotoElsewhere(Data([2]))
        #expect(api.profile.photoVersion == 1 && api.profile.photoGeneration == 3)
        _ = try await workspace.loadSelfProfile()
        // Même photoVersion que le cache : seule la génération désigne le remplacement.
        #expect(workspace.selfPhoto?.data == Data([2]) && workspace.selfPhoto?.generation == 3)
        #expect(workspace.photo(for: api.profile.personId) == Data([2]))
    }

    @Test func aDeviceThatSawTheRemovalShowsNoPhotoThenLoadsTheReplacement() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        startWithPhoto(api, bytes: Data([1]))
        let workspace = await make(api, store)
        let person = api.profile.personId

        api.changePhotoElsewhere(nil)
        _ = try await workspace.loadSelfProfile()
        #expect(workspace.selfPhoto == nil && workspace.photo(for: person) == nil)

        api.changePhotoElsewhere(Data([2]))
        _ = try await workspace.loadSelfProfile()
        #expect(workspace.selfPhoto?.data == Data([2]) && workspace.photo(for: person) == Data([2]))
    }

    @Test func aLateReadOfTheOldPhotoNeverOverwritesTheReplacement() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        startWithPhoto(api, bytes: Data([1]))
        let workspace = await make(api, store, readsProfile: false)
        api.holdsNextPhotoRead = true
        let stale = Task { _ = try? await workspace.loadSelfProfile() }
        await eventually { api.releasePhotoRead != nil }

        // Pendant que la lecture de l'ancienne photo est en l'air, l'école change deux fois de photo.
        api.changePhotoElsewhere(nil)
        api.changePhotoElsewhere(Data([2]))
        _ = try await workspace.loadSelfProfile()
        #expect(workspace.selfPhoto?.data == Data([2]))

        let release = api.releasePhotoRead; api.releasePhotoRead = nil
        release?.resume()
        await stale.value
        // La réponse tardive porte l'identité (version 1, génération 1) : le profil confirmé est à la génération 3.
        #expect(workspace.selfPhoto?.data == Data([2]) && workspace.selfPhoto?.generation == 3)
        #expect(workspace.photo(for: api.profile.personId) == Data([2]))
    }

    @Test func aPhotoChoiceIsNeverSilentlyRebasedOntoAnotherPhotoStateWithTheSameVersion() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        api.profile = SchoolSelfProfile(personId: api.profile.personId, displayName: "Compte test",
            photoVersion: nil, photoGeneration: 1, version: 1)
        let workspace = await make(api, store)
        let id = try workspace.retainSelfPhoto(Data([5]))

        // Sans photo → ajout ailleurs → retrait ailleurs → sans photo : photoVersion est redevenue nil.
        api.changePhotoElsewhere(Data([9]))
        api.changePhotoElsewhere(nil)
        #expect(api.profile.photoVersion == nil && api.profile.photoGeneration == 3 && api.profile.version == 3)
        #expect(await workspace.refreshAccount(minimumInterval: 0))

        do { _ = try await workspace.sendSelfProfileIntent(id); Issue.record("Le changement de photo devait être signalé") }
        catch { #expect(error as? SchoolSelfProfileFailure == .changed) }
        // Rien n'est parti, le choix est conservé, et la lecture fraîche est celle de l'école.
        #expect(api.writes.isEmpty && workspace.hasPendingSelfProfile)
        #expect(workspace.confirmedSelfProfile?.photoGeneration == 3)
        #expect(store.values.values.first?.photo?.jpeg == Data([5]) && store.values.values.first?.attempted == nil)
    }

    @Test func anOldAPIWithoutGenerationKeepsTheVersionOnlyComparisonAsADocumentedLimit() async throws {
        let api = SelfIntentAPI(), store = SelfIntentMemoryStore()
        api.emitsGeneration = false
        let workspace = await make(api, store)
        let id = try workspace.retainSelfPhoto(Data([5]))
        api.changePhotoElsewhere(Data([9]))
        api.changePhotoElsewhere(nil)
        #expect(api.profile.photoGeneration == nil && api.profile.version == 3)
        #expect(await workspace.refreshAccount(minimumInterval: 0))
        // Sans génération, un aller-retour sans photo est invisible : le comportement d'avant #450 est conservé.
        #expect(try await workspace.sendSelfProfileIntent(id))
        #expect(api.writes.map(\.version) == [3] && api.photo == Data([5]))
    }

    @Test func photoStateComparisonNeverAssumesEqualityWhenAGenerationIsMissing() throws {
        let person = UUID()
        func profile(_ version: Int?, _ generation: Int?, of id: UUID? = nil) -> SchoolSelfProfile {
            SchoolSelfProfile(personId: id ?? person, displayName: "P", photoVersion: version, photoGeneration: generation, version: 1)
        }
        #expect(profile(nil, 1).hasSamePhotoState(as: profile(nil, 1)))
        #expect(!profile(nil, 1).hasSamePhotoState(as: profile(nil, 3)))        // sans photo → ailleurs → sans photo
        #expect(!profile(2, 4).hasSamePhotoState(as: profile(2, 5)))
        #expect(!profile(2, nil).hasSamePhotoState(as: profile(2, 5)))          // génération d'un seul côté : non prouvé
        #expect(!profile(2, 5).hasSamePhotoState(as: profile(2, nil)))
        #expect(profile(2, nil).hasSamePhotoState(as: profile(2, nil)))         // ancienne API : version seule
        #expect(!profile(nil, nil).hasSamePhotoState(as: profile(1, nil)))
        #expect(!profile(1, 1).hasSamePhotoState(as: profile(1, 1, of: UUID())))

        let cached = SchoolProfilePhoto(personID: person, version: 2, generation: 5, data: Data([1]))
        #expect(cached.matches(profile(2, 5)) && !cached.matches(profile(2, 6)) && !cached.matches(profile(2, nil)))
        #expect(!cached.matches(profile(2, 5, of: UUID())))
        #expect(!SchoolProfilePhoto(personID: person, version: 2, data: Data([1])).matches(profile(2, 5)))

        let older = #"{"personId":"\#(person.uuidString)","displayName":"P","photoVersion":2,"version":4}"#
        let decoded = try JSONDecoder().decode(SchoolSelfProfile.self, from: Data(older.utf8))
        #expect(decoded.photoGeneration == nil && decoded.photoVersion == 2)
        let newer = #"{"personId":"\#(person.uuidString)","displayName":"P","photoVersion":null,"photoGeneration":9,"version":4}"#
        let current = try JSONDecoder().decode(SchoolSelfProfile.self, from: Data(newer.utf8))
        #expect(current.photoGeneration == 9 && current.photoVersion == nil)
    }

    @Test func theEncryptedPhotoIntentKeepsItsBaseGenerationAndOlderArchivesStayConservative() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProfileGeneration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolSelfProfileIntentStore(directory: directory, keyData: Data(repeating: 0x4A, count: 32))
        let person = UUID()
        let scope = AccountIntentScope(personID: person, apiBaseURL: baseURL.absoluteString)
        let base = SchoolSelfProfile(personId: person, displayName: "P", photoVersion: 3, photoGeneration: 7, version: 2)
        let intent = SchoolSelfProfileIntent(id: UUID(), kind: .photo, base: base, fields: nil, jpeg: Data([1]))
        try store.save(SchoolSelfProfileIntents(photo: intent), scope: scope)
        let restored = try #require(try store.read(scope: scope)?.photo)
        #expect(restored.base.photoGeneration == 7 && restored == intent)
        #expect(restored.baseStillMatches(base))
        #expect(!restored.baseStillMatches(SchoolSelfProfile(personId: person, displayName: "P", photoVersion: 3,
                                                             photoGeneration: 8, version: 3)))

        // Archive écrite avant #450 : le champ est absent, il se relit comme « inconnu » et rien n'est supposé égal.
        let legacyBase = SchoolSelfProfile(personId: person, displayName: "P", photoVersion: 3, version: 2)
        let legacy = SchoolSelfProfileIntents(photo: SchoolSelfProfileIntent(id: UUID(), kind: .photo, base: legacyBase,
                                                                           fields: nil, jpeg: Data([1])))
        let json = try JSONEncoder().encode(legacy)
        #expect(!String(decoding: json, as: UTF8.self).contains("photoGeneration"))
        let reopened = try #require(try JSONDecoder().decode(SchoolSelfProfileIntents.self, from: json).photo)
        #expect(reopened.baseStillMatches(legacyBase))
        #expect(!reopened.baseStillMatches(SchoolSelfProfile(personId: person, displayName: "P", photoVersion: 3,
                                                             photoGeneration: 4, version: 2)))
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
    /// Faux : une école qui ne publie pas `photoGeneration` (ancienne API).
    var emitsGeneration = true
    var holdsNextPhotoRead = false
    var releasePhotoRead: CheckedContinuation<Void, Never>?

    /// Autre appareil : la photo change à l'école sans que celui-ci le sache (ajout, remplacement ou retrait).
    func changePhotoElsewhere(_ jpeg: Data?) {
        profile = SchoolSelfProfile(personId: profile.personId, displayName: profile.displayName,
            photoVersion: jpeg == nil ? nil : (profile.photoVersion ?? 0) + 1,
            photoGeneration: emitsGeneration ? (profile.photoGeneration ?? 0) + 1 : nil, version: profile.version + 1)
        photo = jpeg
    }

    func me() async throws -> SchoolPerson {
        SchoolPerson(personId: profile.personId, version: profile.version, displayName: profile.displayName,
            locale: "fr", memberships: memberships)
    }
    func selfProfile() async throws -> SchoolSelfProfile {
        if failReads { throw SchoolAPIError.unavailable }
        return profile
    }
    func personPhoto(personID: UUID) async throws -> Data? {
        let snapshot = photo                                     // octets servis au départ de la lecture
        if holdsNextPhotoRead { holdsNextPhotoRead = false; await withCheckedContinuation { releasePhotoRead = $0 } }
        return snapshot
    }
    func saveSelfProfile(_ edit: SchoolSelfProfileEdit, version: Int) async throws -> SchoolSelfProfile {
        writes.append(Write(kind: .fields, version: version, jpeg: nil))
        guard version == profile.version else { throw SchoolSelfProfileFailure.changed }
        let base = SchoolSelfProfile(personId: profile.personId, displayName: profile.displayName,
            photoVersion: profile.photoVersion, photoGeneration: profile.photoGeneration, version: version + 1)
        profile = SchoolSelfProfileIntent.projecting(edit, on: base)
        return try await committed(profile)
    }
    func setSelfPhoto(_ jpeg: Data?, version: Int) async throws -> SchoolSelfProfile {
        writes.append(Write(kind: .photo, version: version, jpeg: jpeg))
        guard version == profile.version else { throw SchoolSelfProfileFailure.changed }
        let edit = SchoolSelfProfileEdit(profile)
        let base = SchoolSelfProfile(personId: profile.personId, displayName: profile.displayName,
            photoVersion: jpeg == nil ? nil : (profile.photoVersion ?? 0) + 1,
            photoGeneration: emitsGeneration ? (profile.photoGeneration ?? 0) + 1 : nil, version: version + 1)
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
