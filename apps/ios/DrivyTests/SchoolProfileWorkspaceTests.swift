import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolProfileWorkspaceTests {
    @Test func readingNeverInventsNamesOrSubmitsACommand() async {
        let api = ProfileAPIStub(); api.profileValue = ProfileFixture.profile(firstName: nil, lastName: nil)
        let model = ProfileFixture.workspace(api: api)
        await model.load()
        #expect(model.draft.firstName.isEmpty && model.draft.lastName.isEmpty)
        #expect(api.commands.isEmpty && !model.hasEdits)
        #expect(model.editableFields.contains(.firstName))
    }
    @Test func instructorWritesOnlyContactsWithSharedVersionAndDistinctRoute() async throws {
        let api = ProfileAPIStub(); let box = ConfigurationOutboxStub()
        let model = ProfileFixture.workspace(api: api, box: box, roles: ["INSTRUCTOR"])
        await model.load(); model.draft.contactPhone = "+41 79 123 45 67"; model.draft.firstName = "Interdit"
        #expect(model.editableFields == [.contactEmail, .contactPhone])
        #expect(await model.saveProfileAfterConfirmation())
        let command = try #require(api.commands.first)
        let body = try JSONDecoder().decode([String: SchoolProfileValue].self, from: command.body)
        #expect(Set(body.keys) == ["operationId", "policyVersionId", "contactPhone"])
        #expect(command.resourceID == ProfileFixture.profileID)
        #expect(command.routeResourceID == ProfileFixture.learnerID)
        #expect(command.resourceVersion == 1 && box.saves == [command, command])
        #expect(box.value == nil)
    }
    @Test func uncertainMutationSurvivesRestartWithOriginalBytesAndScope() async throws {
        let api = ProfileAPIStub(); api.sendFailure = .unavailable
        let box = ConfigurationOutboxStub(); let model = ProfileFixture.workspace(api: api, box: box)
        await model.load(); model.draft.contactPhone = "0123456"
        #expect(await model.saveProfileAfterConfirmation() == false)
        let command = try #require(box.value)
        let reopened = ProfileFixture.workspace(api: api, box: box)
        await reopened.load(); #expect(!reopened.canMutate)
        api.sendFailure = nil; await reopened.retryPending()
        #expect(api.commands == [command, command] && box.saves == [command, command, command])
        #expect(box.value == nil)
    }
    @Test func freshConflictAllowsCorrectionButRetryConflictKeepsUncertainty() async throws {
        let api = ProfileAPIStub(); let box = ConfigurationOutboxStub(); let model = ProfileFixture.workspace(api: api, box: box)
        await model.load(); model.draft.contactPhone = "0123456"; api.sendFailure = .conflict
        #expect(await model.saveProfileAfterConfirmation() == false)
        #expect(box.value == nil && model.needsReload && model.draft.contactPhone == "0123456")
        await model.load(); api.sendFailure = .unavailable
        #expect(await model.saveProfileAfterConfirmation() == false)
        let command = try #require(box.value)
        api.sendFailure = .conflict; await model.retryPending()
        #expect(box.value == command && model.pendingRequiresReview && !model.canRetryPending)
    }
    @Test func reloadRebasesOnlyEditedFieldsAndKeepsConcurrentEmailChange() async {
        let api = ProfileAPIStub(); let model = ProfileFixture.workspace(api: api)
        await model.load(); model.draft.contactPhone = "Mon changement"
        api.profileValue = ProfileFixture.profile(version: 2, email: "nouveau@example.invalid")
        await model.load()
        #expect(model.draft.contactPhone == "Mon changement")
        #expect(model.draft.contactEmail == "nouveau@example.invalid")
        #expect(model.draft.changes(from: api.profileValue, allowed: model.editableFields).keys.sorted() == ["contactPhone"])
    }
    @Test func changedAccessEpochOrOtherLearnerNeverReplaysPendingMutation() async throws {
        let command = try ProfileFixture.command()
        let api = ProfileAPIStub(); let box = ConfigurationOutboxStub(value: command)
        let model = SchoolProfileWorkspace(scope: ConfigurationFixture.scope(epoch: 2), roles: ["ADMIN"],
            learnerID: ProfileFixture.learnerID, api: api, outbox: box)
        await model.load(); await model.retryPending()
        #expect(model.profile != nil && !model.canRetryPending && api.commands.isEmpty)
        api.receipt = ProfileFixture.receipt(command, id: UUID()); await model.verifyPending()
        #expect(box.value == command)
        api.receipt = ProfileFixture.receipt(command); await model.verifyPending()
        #expect(box.value == nil)
    }
    @Test func durabilityFailurePreventsEmissionButAllowsReading() async {
        let api = ProfileAPIStub(); let box = ConfigurationOutboxStub(); box.failRead = true
        let model = ProfileFixture.workspace(api: api, box: box)
        await model.load(); #expect(model.profile != nil && !model.canMutate)
        box.failRead = false; await model.load(); box.failSave = true; model.draft.contactPhone = "0123"
        #expect(await model.saveProfileAfterConfirmation() == false)
        #expect(api.commands.isEmpty)
    }
    @Test func policyCreationUsesSchoolVersionAndDoesNotPublishAutomatically() async throws {
        let api = ProfileAPIStub(); let box = ConfigurationOutboxStub()
        let model = SchoolProfileWorkspace(scope: ConfigurationFixture.scope(), roles: ["ADMIN"], api: api, outbox: box)
        await model.load(); let draft = ProfileFixture.policyDraft()
        #expect(await model.createPolicyAfterConfirmation(draft))
        let command = try #require(api.commands.first)
        #expect(command.kind == .createProfilePolicy && command.resourceVersion == 0 && command.expectedVersion == 8)
        #expect(api.commands.count == 1 && api.policyValues.last?.status == "DRAFT")
        let created = try #require(api.policyValues.last)
        await model.preparePublication(created)
        #expect(await model.publishAfterConfirmation(created))
        #expect(api.commands.last?.kind == .publishProfilePolicy)
        #expect(api.commands.last?.resourceID == created.id)
    }
    @Test func publicationRequiresExactAdoptedNoticeAndNeverUsesLatestNoticeByAccident() async {
        let api = ProfileAPIStub(); let policy = ProfileFixture.policy(status: "DRAFT", version: 1)
        api.policyValues = [policy]
        var latest = ProfileFixture.notice(); latest.noticeVersionId = UUID(); api.noticeValue = latest
        let model = SchoolProfileWorkspace(scope: ConfigurationFixture.scope(), roles: ["ADMIN"], api: api, outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(await model.publishAfterConfirmation(policy) == false)
        await model.preparePublication(policy)
        #expect(!model.canPublish(policy) && model.publicationNotice == nil)
        #expect(api.noticeRequests.last == policy.noticeVersionId)
        api.noticeValue = ProfileFixture.notice()
        await model.preparePublication(policy)
        #expect(model.canPublish(policy) && model.publicationNotice?.noticeVersionId == policy.noticeVersionId)
        #expect(api.commands.isEmpty)
    }
    @Test func photoCannotBecomeRequiredAndPolicyWithoutAdoptedNoticeCannotBeCreated() async {
        var draft = ProfileFixture.policyDraft(); draft.included.insert(.profilePhotoDocumentId)
        let index = SchoolProfileField.allCases.firstIndex(of: .profilePhotoDocumentId)!
        draft.rules[index].explanation = "Personnaliser l’espace"
        draft.rules[index].requirement = .required
        #expect(!draft.isValid)
        let api = ProfileAPIStub(); api.noticeValue = ConfigurationFixture.policy()
        let model = SchoolProfileWorkspace(scope: ConfigurationFixture.scope(), roles: ["ADMIN"], api: api, outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(!model.canCreatePolicy)
        #expect(await model.createPolicyAfterConfirmation(ProfileFixture.policyDraft()) == false)
    }
    @Test func canonicalPolicyIsLoadedBeyondFirstPageWithoutDeviceClockGuess() async {
        let api = ProfileAPIStub()
        api.firstPage = .init(items: [], nextCursor: "canonical-next")
        let model = ProfileFixture.workspace(api: api)
        await model.load()
        #expect(model.applicablePolicy?.id == ProfileFixture.policyID)
        #expect(api.cursors.count == 2 && api.cursors[1] == "canonical-next")
    }
    @Test func unauthorizedResponsePurgesDraftButRetainsDurablePending() async throws {
        let command = try ProfileFixture.command(); let api = ProfileAPIStub(); let box = ConfigurationOutboxStub(value: command)
        let model = ProfileFixture.workspace(api: api, box: box)
        await model.load(); model.draft.firstName = "Privé"; api.readFailure = .forbidden
        await model.load()
        #expect(model.profile == nil && model.draft.firstName.isEmpty && model.accessFailure == .forbidden)
        #expect(box.value == command)
    }
    @Test func delayedReadCannotRestoreAClosedProfile() async {
        let api = ProfileAPIStub(); let latch = ProfileReadLatch()
        api.schoolHandler = { await latch.wait() }
        let model = ProfileFixture.workspace(api: api)
        let task = Task { await model.load() }
        await latch.started(); model.invalidate(); latch.resolve()
        await task.value
        #expect(model.school == nil && model.profile == nil && model.policies.isEmpty)
    }
    @Test func optionalDeviceStepsAndCompletionAreSeparateExplicitCommands() async throws {
        let api = ProfileAPIStub()
        let model = SchoolProfileWorkspace(scope: ConfigurationFixture.scope(), roles: ["LEARNER"], learnerID: ProfileFixture.learnerID,
            isOwnProfile: true, onboardingKind: .student, api: api, outbox: ConfigurationOutboxStub())
        await model.load(); #expect(api.commands.isEmpty)
        #expect(await model.saveOnboarding(step: .review, skipOptional: true))
        let body = try JSONSerialization.jsonObject(with: api.commands[0].body) as? [String: Any]
        #expect(Set(body?["skippedOptionalSteps"] as? [String] ?? []) == ["PHOTO", "NOTIFICATIONS", "DEVICE"])
        #expect(api.commands.count == 1)
        #expect(await model.completeOnboardingAfterConfirmation())
        #expect(api.commands.last?.kind == .completeOnboarding && model.onboarding?.status == "COMPLETED")
    }
    @Test func civilDatesRejectImpossibleAndFutureDatesWithoutTimezoneConversion() {
        #expect(SchoolProfileDraft.civilDate("29.02.2024") == "2024-02-29")
        #expect(SchoolProfileDraft.civilDate("29.02.2025") == nil)
        #expect(SchoolProfileDraft.civilDate("2024-02-29") == nil)
        var draft = SchoolProfileDraft(ProfileFixture.profile()); draft.birthDate = "01.01.2999"
        #expect(!draft.isValid(allowed: [.birthDate], timeZone: "Europe/Zurich"))
    }
    @Test func legacyConfigurationCannotRetryAProfileCommand() async throws {
        let command = try ProfileFixture.command(); let box = ConfigurationOutboxStub(value: command)
        let api = ConfigurationAPIStub(); let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: box)
        await model.load(); await model.retryPending()
        #expect(!model.canRetryPending && api.commands.isEmpty && box.value == command)
    }
}

@MainActor
final class ProfileAPIStub: SchoolProfileAPI {
    var profileValue = ProfileFixture.profile()
    var policyValues = [ProfileFixture.policy()]
    var noticeValue = ProfileFixture.notice()
    var onboardingValue = ProfileFixture.onboarding()
    var firstPage: SchoolPage<SchoolProfilePolicy>?
    var readFailure: SchoolProfileFailure?
    var sendFailure: SchoolProfileFailure?
    var receipt: SchoolOperationReceipt?
    var schoolHandler: (() async -> SchoolDetails)?
    var commands: [PendingSchoolCommand] = []
    var cursors: [String?] = []
    var noticeRequests: [UUID?] = []
    func school(id: UUID) async throws -> SchoolDetails {
        if let readFailure { throw readFailure }
        if let schoolHandler { return await schoolHandler() }
        return ConfigurationFixture.school(version: 8, status: "ACTIVE")
    }
    func policies(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolProfilePolicy> {
        cursors.append(cursor)
        if cursor == nil, let firstPage { return firstPage }
        return .init(items: policyValues, nextCursor: nil)
    }
    func notice(schoolID: UUID, id: UUID?) async throws -> SchoolDataPolicy { noticeRequests.append(id); return noticeValue }
    func profile(schoolID: UUID, learnerID: UUID) async throws -> SchoolAdministrativeProfile { profileValue }
    func readiness(schoolID: UUID, learnerID: UUID, action: String) async throws -> SchoolLearnerReadiness {
        .init(learnerId: learnerID, action: action, resourceId: nil, ready: true, blockers: [], policyVersionId: ProfileFixture.policyID, computedAt: ConfigurationFixture.timestamp)
    }
    func onboarding(schoolID: UUID, kind: SchoolOnboardingKind) async throws -> SchoolOnboarding { onboardingValue }
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt {
        guard let receipt else { throw SchoolProfileFailure.operationUnknown }; return receipt
    }
    func send(_ command: PendingSchoolCommand) async throws -> SchoolProfileResult {
        commands.append(command)
        if let sendFailure { throw sendFailure }
        switch command.kind {
        case .updateProfile:
            let body = try JSONDecoder().decode([String: SchoolProfileValue].self, from: command.body)
            var phone = profileValue.contactPhone
            if case .text(let value)? = body["contactPhone"] { phone = value }
            profileValue = ProfileFixture.profile(version: command.resourceVersion + 1, phone: phone)
            return .profile(profileValue)
        case .createProfilePolicy:
            let value = ProfileFixture.policy(id: UUID(), status: "DRAFT", version: 1)
            policyValues.append(value); return .policy(value)
        case .publishProfilePolicy:
            let value = ProfileFixture.policy(id: command.resourceID!, status: "PUBLISHED", version: command.resourceVersion + 1)
            policyValues.removeAll { $0.id == value.id }; policyValues.append(value); return .policy(value)
        case .saveOnboarding, .completeOnboarding:
            onboardingValue = ProfileFixture.onboarding(version: command.resourceVersion + 1,
                status: command.kind == .completeOnboarding ? "COMPLETED" : "READY", step: .review)
            return .onboarding(onboardingValue)
        default: throw SchoolProfileFailure.invalidResponse
        }
    }
}

@MainActor
enum ProfileFixture {
    static let profileID = UUID(uuidString: "41000000-0000-4000-8000-000000000001")!
    static let learnerID = UUID(uuidString: "41000000-0000-4000-8000-000000000002")!
    static let policyID = UUID(uuidString: "41000000-0000-4000-8000-000000000003")!
    static let noticeID = UUID(uuidString: "41000000-0000-4000-8000-000000000004")!
    static let onboardingID = UUID(uuidString: "41000000-0000-4000-8000-000000000005")!
    static func profile(version: Int = 1, firstName: String? = "Alice", lastName: String? = "Exemple",
        email: String? = "alice@example.invalid", phone: String? = nil) -> SchoolAdministrativeProfile {
        .init(id: profileID, schoolId: ConfigurationFixture.schoolID, version: version, learnerId: learnerID,
            firstName: firstName, lastName: lastName, birthDate: nil, postalAddress: nil, contactEmail: email,
            contactPhone: phone, profilePhotoDocumentId: nil, updatedAt: ConfigurationFixture.timestamp,
            enteredByMembershipId: ConfigurationFixture.membershipID, entrySource: "SELF", policyVersionId: policyID)
    }
    static func policy(id: UUID = policyID, status: String = "PUBLISHED", version: Int = 2) -> SchoolProfilePolicy {
        .init(id: id, schoolId: ConfigurationFixture.schoolID, version: version, status: status, effectiveFrom: "2020-01-01T00:00:00Z",
            fields: policyDraft().selectedRules, noticeVersionId: noticeID, approvedByMembershipId: status == "DRAFT" ? nil : ConfigurationFixture.membershipID)
    }
    static func policyDraft() -> SchoolProfilePolicyDraft {
        var draft = SchoolProfilePolicyDraft(); draft.included = [.firstName, .lastName, .contactEmail, .contactPhone]
        for index in draft.rules.indices {
            draft.rules[index].explanation = draft.rules[index].field.isName ? "Identifier la personne dans le dossier scolaire." : "Contacter la personne pour organiser son enseignement."
        }
        return draft
    }
    static func notice() -> SchoolDataPolicy {
        var value = ConfigurationFixture.policy(approved: true); value.noticeVersionId = noticeID; return value
    }
    static func onboarding(version: Int = 1, status: String = "IN_PROGRESS", step: SchoolOnboardingStep = .identity) -> SchoolOnboarding {
        .init(id: onboardingID, schoolId: ConfigurationFixture.schoolID, version: version, personId: ConfigurationFixture.personID,
            membershipId: ConfigurationFixture.membershipID, kind: .student, status: status, currentStep: step,
            skippedOptionalSteps: [], policyVersionId: policyID, lastSavedAt: ConfigurationFixture.timestamp,
            pendingActions: step == .review ? [] : [.init(code: "ONBOARDING_REVIEW_REQUIRED", message: "Relisez votre arrivée.", field: nil, purpose: nil, resourceId: nil, destinationKey: "PROFILE")],
            returnDestinationKey: nil, returnResourceId: nil)
    }
    static func workspace(api: ProfileAPIStub, box: ConfigurationOutboxStub = ConfigurationOutboxStub(), roles: [String] = ["ADMIN"]) -> SchoolProfileWorkspace {
        .init(scope: ConfigurationFixture.scope(), roles: roles, learnerID: learnerID, api: api, outbox: box)
    }
    static func command() throws -> PendingSchoolCommand {
        let id = UUID()
        return .init(id: id, scope: ConfigurationFixture.scope(), kind: .updateProfile, resourceVersion: 1,
            createdAt: Date(), body: try JSONEncoder().encode(["operationId": id.uuidString, "policyVersionId": policyID.uuidString, "contactPhone": "0123"]),
            resourceID: profileID, routeResourceID: learnerID)
    }
    static func receipt(_ command: PendingSchoolCommand, id: UUID? = nil) -> SchoolOperationReceipt {
        .init(operationId: command.id, commandType: command.kind.operationType, resourceType: command.kind.resourceType,
            resourceId: id ?? command.resourceID ?? policyID, committedAt: ConfigurationFixture.timestamp, resourceVersion: command.resourceVersion + 1)
    }
}
@MainActor private final class ProfileReadLatch {
    private var continuation: CheckedContinuation<SchoolDetails, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    func wait() async -> SchoolDetails {
        await withCheckedContinuation { continuation in
            self.continuation = continuation; startedContinuation?.resume(); startedContinuation = nil
        }
    }
    func started() async {
        if continuation != nil { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func resolve() { continuation?.resume(returning: ConfigurationFixture.school(status: "ACTIVE")); continuation = nil }
}
