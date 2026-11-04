import Foundation
import Testing
@testable import Drivy

/// #120 : la saisie de l'accueil guidé vit dans le coffre chiffré du compte avant l'envoi, sans jamais
/// restaurer une acceptation. Fixtures synthétiques uniquement.
@MainActor struct SchoolOnboardingDraftTests {
    private let key = Data(repeating: 0x6b, count: 32)

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-draft-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeWorkspace(api: ProfileAPIStub, store: any SchoolOnboardingDraftStore,
                               scope: SchoolCommandScope = ConfigurationFixture.scope()) -> SchoolProfileWorkspace {
        SchoolProfileWorkspace(scope: scope, roles: ["LEARNER"], learnerID: ProfileFixture.learnerID,
            isOwnProfile: true, onboardingKind: .student, api: api, outbox: ConfigurationOutboxStub(),
            onboardingDraftStore: store, onboardingDraftDelay: .zero)
    }

    private func fieldDraft(phone: String) -> SchoolOnboardingDraftFields {
        var value = SchoolOnboardingDraftFields()
        value.contactPhone = phone
        return value
    }

    @Test func typedFieldsComeBackWithTheLocalStepAndNoAcceptedTerms() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: key)
        let api = ProfileAPIStub()
        let first = makeWorkspace(api: api, store: store)
        await first.load()
        first.draft.contactPhone = "0791112233"
        #expect(first.hasOnboardingDraft)
        // L'étape locale reste celle du brouillon, distincte de l'étape confirmée par l'école.
        #expect(first.onboardingLocalStep == .identity && first.onboarding?.currentStep == .identity)

        // Le coffre ne laisse rien en clair sur le disque.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        let bytes = try Data(contentsOf: #require(files.first))
        #expect(bytes.range(of: Data("0791112233".utf8)) == nil)

        let stored = try #require(try store.read(scope: ConfigurationFixture.scope(), kind: .student))
        #expect(stored.onboardingID == ProfileFixture.onboardingID && stored.version == 1)
        // Aucune condition, aucun consentement, aucune autorisation n'est conservée comme acceptée.
        let encoded = try JSONEncoder().encode(stored)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let forbidden = ["accept", "consent", "permission", "authoriz", "condition", "terms"]
        let names = recursiveKeys(object)
        let storesAnAcceptance = names.contains { name in
            forbidden.contains { name.lowercased().contains($0) }
        }
        #expect(!storesAnAcceptance)

        let reopened = makeWorkspace(api: api, store: store)
        await reopened.load()
        #expect(reopened.hasOnboardingDraft)
        #expect(reopened.draft.contactPhone == "0791112233")
        // Un champ non saisi vient toujours du serveur, jamais d'un ancien brouillon.
        #expect(reopened.draft.firstName == "Alice")
        #expect(reopened.onboarding?.currentStep == .identity && reopened.onboardingLocalStep == .identity)
    }

    @Test func serverConfirmationErasesTheStoredDraft() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: key)
        let api = ProfileAPIStub()
        let model = makeWorkspace(api: api, store: store)
        await model.load()
        model.draft.contactPhone = "0791112233"
        #expect(model.hasOnboardingDraft)
        #expect(await model.saveProfileAfterConfirmation())
        #expect(!model.hasOnboardingDraft && model.onboardingLocalStep == nil)
        #expect(try store.read(scope: ConfigurationFixture.scope(), kind: .student) == nil)

        let reopened = makeWorkspace(api: api, store: store)
        await reopened.load()
        #expect(!reopened.hasOnboardingDraft && !reopened.hasEdits)
        #expect(reopened.draft.contactPhone == "0791112233")
    }

    @Test func anotherAccountSchoolEpochOrKindNeverSeesTheDraft() throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: key)
        let scope = ConfigurationFixture.scope()
        let draft = SchoolOnboardingDraft(onboardingID: ProfileFixture.onboardingID, version: 1,
            base: SchoolOnboardingDraftFields(), edited: fieldDraft(phone: "0791112233"), step: .identity, savedAt: Date())
        try store.save(draft, scope: scope, kind: .student)
        #expect(try store.read(scope: scope, kind: .student) == draft)

        let otherPerson = SchoolCommandScope(personID: UUID(), schoolID: scope.schoolID,
            membershipID: scope.membershipID, accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL)
        let otherSchool = SchoolCommandScope(personID: scope.personID, schoolID: UUID(),
            membershipID: scope.membershipID, accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL)
        let otherMembership = SchoolCommandScope(personID: scope.personID, schoolID: scope.schoolID,
            membershipID: UUID(), accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL)
        #expect(try store.read(scope: otherPerson, kind: .student) == nil)
        #expect(try store.read(scope: otherSchool, kind: .student) == nil)
        #expect(try store.read(scope: otherMembership, kind: .student) == nil)
        #expect(try store.read(scope: ConfigurationFixture.scope(epoch: 2), kind: .student) == nil)
        #expect(try store.read(scope: scope, kind: .staff) == nil)
    }

    @Test func signingOutPurgesTheDraftLikeTheOtherIntentJournals() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: key)
        let api = ProfileAPIStub()
        let model = makeWorkspace(api: api, store: store)
        await model.load()
        model.draft.contactPhone = "0791112233"
        #expect(model.hasOnboardingDraft)

        model.purgeOnboardingDraft()
        #expect(!model.hasOnboardingDraft && model.onboardingLocalStep == nil)
        #expect(try store.read(scope: ConfigurationFixture.scope(), kind: .student) == nil)

        let reopened = makeWorkspace(api: api, store: store)
        await reopened.load()
        #expect(!reopened.hasOnboardingDraft)
    }

    @Test func abandoningTheDraftForgetsTypedFieldsWithoutTouchingTheServerProfile() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: key)
        let api = ProfileAPIStub()
        let model = makeWorkspace(api: api, store: store)
        await model.load()
        model.draft.contactPhone = "0791112233"
        #expect(model.hasOnboardingDraft)

        model.abandonOnboardingDraft()
        #expect(!model.hasOnboardingDraft && !model.hasEdits)
        #expect(model.draft.contactPhone == "")
        #expect(api.commands.isEmpty)
    }

    @Test func aStepReachedLocallyStaysDistinctUntilTheSchoolConfirmsIt() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: key)
        let api = ProfileAPIStub()
        let model = makeWorkspace(api: api, store: store)
        await model.load()
        api.sendFailure = .unavailable
        #expect(await model.saveOnboarding(step: .formations) == false)
        // Rien n'est confirmé par l'école, mais l'étape atteinte ici est conservée à part.
        #expect(model.onboarding?.currentStep == .identity)
        #expect(model.onboardingLocalStep == .formations)
        #expect(model.hasOnboardingDraft)

        let reopened = makeWorkspace(api: api, store: store)
        await reopened.load()
        #expect(reopened.onboarding?.currentStep == .identity)
        #expect(reopened.onboardingLocalStep == .formations)
        #expect(reopened.hasOnboardingDraft)
    }

    @Test func aConfirmedStepErasesTheStepDraft() async throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolOnboardingDraftStore(directory: directory, keyData: key)
        let api = ProfileAPIStub()
        let model = makeWorkspace(api: api, store: store)
        await model.load()
        #expect(await model.saveOnboarding(step: .formations))
        #expect(model.onboarding?.currentStep == .formations)
        #expect(!model.hasOnboardingDraft && model.onboardingLocalStep == nil)
    }

    private func recursiveKeys(_ value: Any) -> Set<String> {
        guard let object = value as? [String: Any] else { return [] }
        var keys = Set(object.keys)
        for child in object.values { keys.formUnion(recursiveKeys(child)) }
        return keys
    }
}
