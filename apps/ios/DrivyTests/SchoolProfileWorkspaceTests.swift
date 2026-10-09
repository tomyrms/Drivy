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
    @Test func editableFieldsFollowServerRightsNotThePolicyList() async {
        // Politique limitée au prénom et au nom, comme celle de l’école d’essai.
        let api = ProfileAPIStub(); api.policyValues = [ProfileFixture.policy(fields: [.firstName, .lastName])]
        let admin = ProfileFixture.workspace(api: api)
        await admin.load()
        #expect(admin.editableFields == [.firstName, .lastName, .birthDate, .postalAddress, .contactEmail, .contactPhone])
        #expect(admin.requestedFields == [.firstName, .lastName])
        let own = SchoolProfileWorkspace(scope: ConfigurationFixture.scope(), roles: ["LEARNER"], learnerID: ProfileFixture.learnerID,
            isOwnProfile: true, api: api, outbox: ConfigurationOutboxStub())
        await own.load()
        #expect(own.editableFields == SchoolProfileWorkspace.fullAccessFields)
        let instructor = ProfileFixture.workspace(api: api, roles: ["INSTRUCTOR"])
        await instructor.load()
        #expect(instructor.editableFields == [.contactEmail, .contactPhone])
        // Sans politique applicable, le serveur refuse toute écriture : rien n’est proposé.
        let unread = ProfileFixture.workspace(api: api)
        #expect(unread.editableFields.isEmpty && unread.requestedFields.isEmpty)
    }
    @Test func fullAccessSavesFieldsOutsideThePolicyAndReadsBackTheServerAnswer() async throws {
        let api = ProfileAPIStub(); api.policyValues = [ProfileFixture.policy(fields: [.firstName, .lastName])]
        let box = ConfigurationOutboxStub(); let model = ProfileFixture.workspace(api: api, box: box)
        await model.load()
        let address = SchoolPostalAddress(line1: "Rue des Exemples 12", line2: nil, postalCode: "2053", locality: "Cernier", countryCode: "CH")
        model.draft.lastName = "Modèle"; model.draft.birthDate = "12.07.2005"
        model.draft.contactEmail = "contact@example.invalid"; model.draft.contactPhone = "+41 00 000 00 00"
        model.draft.hasAddress = true; model.draft.address = address
        #expect(model.invalidFields.isEmpty && model.canSaveProfile)
        #expect(await model.saveProfileAfterConfirmation())
        let command = try #require(api.commands.first)
        let body = try JSONDecoder().decode([String: SchoolProfileValue].self, from: command.body)
        #expect(Set(body.keys) == ["operationId", "policyVersionId", "lastName", "birthDate", "postalAddress", "contactEmail", "contactPhone"])
        #expect(body["birthDate"] == SchoolProfileValue.text("2005-07-12") && body["postalAddress"] == SchoolProfileValue.address(address))
        // Après l’accusé du serveur : la demande quitte la file, le dossier est relu et le brouillon repart de la réponse.
        #expect(box.value == nil && model.pending == nil && !model.hasEdits)
        #expect(model.profile == api.profileValue && model.profile?.version == 2)
        #expect(model.profile?.lastName == "Modèle" && model.profile?.birthDate == "2005-07-12")
        #expect(model.profile?.postalAddress == address && model.profile?.contactPhone == "+41 00 000 00 00")
        #expect(model.draft == SchoolProfileDraft(api.profileValue) && model.draft.birthDate == "12.07.2005")
        // Effacer une valeur enregistrée envoie un null explicite, pas une chaîne vide.
        model.draft.birthDate = ""; model.draft.hasAddress = false
        #expect(await model.saveProfileAfterConfirmation())
        let second = try #require(api.commands.last)
        let clearing = try JSONDecoder().decode([String: SchoolProfileValue].self, from: second.body)
        #expect(api.commands.count == 2 && second.resourceVersion == 2)
        #expect(clearing["birthDate"] == SchoolProfileValue.null && clearing["postalAddress"] == SchoolProfileValue.null)
        #expect(model.profile?.birthDate == nil && model.profile?.postalAddress == nil && model.profile?.version == 3)
    }
    @Test func onlyChangedFieldsAndEditableNamesCanBlockASave() async throws {
        // Une valeur inchangée vient du serveur : elle n’est ni renvoyée ni recontrôlée, même si l’app la jugerait mal formée.
        let api = ProfileAPIStub(); api.profileValue = ProfileFixture.profile(email: "alice@invalid")
        let model = ProfileFixture.workspace(api: api)
        await model.load(); model.draft.contactPhone = "0123456"
        #expect(model.invalidFields.isEmpty && model.canSaveProfile)
        model.draft.birthDate = "31.02.2005"
        #expect(model.invalidFields == [.birthDate] && !model.canSaveProfile)
        model.draft.birthDate = ""; model.draft.contactEmail = "sans-arobase"
        #expect(model.invalidFields == [.contactEmail] && !model.canSaveProfile)
        model.draft.contactEmail = "alice@invalid"
        #expect(await model.saveProfileAfterConfirmation())
        let command = try #require(api.commands.first)
        let body = try JSONDecoder().decode([String: SchoolProfileValue].self, from: command.body)
        #expect(Set(body.keys) == ["operationId", "policyVersionId", "contactPhone"])
        // Prénom et nom restent exigés dès qu’ils sont modifiables ; le moniteur affecté n’y est pas tenu.
        let unnamed = ProfileAPIStub(); unnamed.profileValue = ProfileFixture.profile(firstName: nil, lastName: nil)
        let admin = ProfileFixture.workspace(api: unnamed)
        await admin.load(); admin.draft.contactPhone = "0123456"
        #expect(admin.invalidFields == [.firstName, .lastName] && !admin.canSaveProfile)
        let instructor = ProfileFixture.workspace(api: unnamed, roles: ["INSTRUCTOR"])
        await instructor.load(); instructor.draft.contactPhone = "0123456"
        #expect(instructor.invalidFields.isEmpty && instructor.canSaveProfile)
    }
    @Test func refusedFieldLeavesNoPendingCommandAndKeepsTheDraftForCorrection() async {
        let api = ProfileAPIStub(); let box = ConfigurationOutboxStub(); let model = ProfileFixture.workspace(api: api, box: box)
        await model.load(); model.draft.birthDate = "12.07.2005"
        api.sendFailure = .rejected(SchoolProfileClient.fieldForbiddenMessage)
        #expect(await model.saveProfileAfterConfirmation() == false)
        #expect(api.commands.count == 1 && box.value == nil && model.pending == nil)
        #expect(model.errorMessage == SchoolProfileClient.fieldForbiddenMessage && model.accessFailure == nil)
        #expect(model.profile != nil && model.draft.birthDate == "12.07.2005" && model.needsReload && !model.canMutate)
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
    @Test func anObservationWithdrawalCannotBeVerifiedOrAcknowledgedFromTheProfile() async throws {
        let operation = UUID()
        let body = SchoolObservationBody(operationId: operation, draftId: nil, captureId: nil, segmentId: nil,
            pointSequence: nil, competencyId: nil, text: "Moment marqué", origin: "LIVE",
            observedAt: ConfigurationFixture.timestamp, eventKind: "MARKER", eventStatus: nil)
        let original = PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .createObservation,
            resourceVersion: 0, createdAt: Date(), body: try JSONEncoder().encode(body), routeResourceID: UUID())
        let withdrawal = original.requestingObservationUndo(operationID: UUID())
        let api = ProfileAPIStub(), box = ConfigurationOutboxStub(value: withdrawal)
        api.receipt = ProfileFixture.receipt(original)
        let model = ProfileFixture.workspace(api: api, box: box)
        await model.load()
        #expect(model.profile != nil && !model.canVerifyPending && !model.canRetryPending && !model.canMutate)
        await model.verifyPending()
        #expect(api.operationRequests.isEmpty && api.commands.isEmpty)
        #expect(model.pending == withdrawal && box.value == withdrawal)
        #expect(model.errorMessage == nil && model.successMessage == nil)
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
    @Test func silentRereadKeepsTheFormOpenAndWhatWasTypedMeanwhile() async {
        let api = ProfileAPIStub(); let model = ProfileFixture.workspace(api: api)
        await model.load()
        #expect(model.canMutate && model.acceptsInput && !model.needsReload)
        let latch = ProfileReadLatch()
        api.schoolHandler = { await latch.wait() }
        let reread = Task { await model.load() }
        await latch.started()
        // Relecture en cours : l’envoi est fermé, le formulaire reste ouvert et rien ne se présente comme un enregistrement.
        #expect(model.isLoading && !model.canMutate && model.acceptsInput && !model.needsReload && !model.isSavingProfile)
        model.draft.contactPhone = "0123456"
        latch.resolve(); await reread.value
        api.schoolHandler = nil
        #expect(model.draft.contactPhone == "0123456" && model.hasEdits && model.canSaveProfile)
        // Relecture échouée : l’état de l’école n’est plus connu, la saisie est conservée mais le formulaire attend.
        api.readFailure = .unavailable
        await model.load()
        #expect(model.needsReload && !model.acceptsInput && !model.canMutate && model.draft.contactPhone == "0123456")
        api.readFailure = nil
        await model.load()
        #expect(model.acceptsInput && model.canSaveProfile && model.draft.contactPhone == "0123456")
    }
    @Test func aNormalSaveIsNeverShownAsARequestToVerify() async {
        let api = ProfileAPIStub(); let box = ConfigurationOutboxStub(); let model = ProfileFixture.workspace(api: api, box: box)
        await model.load(); model.draft.contactPhone = "0123456"
        var duringSend: [Bool] = []
        api.onSend = { duringSend = [model.pending != nil, model.pendingAwaitsReview, model.acceptsInput, model.isSavingProfile] }
        #expect(await model.saveProfileAfterConfirmation())
        // Pendant l’envoi : la demande est dans la file sans être « à vérifier » ; la saisie attend la réponse.
        #expect(duringSend == [true, false, false, true])
        #expect(model.pending == nil && !model.pendingAwaitsReview && model.acceptsInput && !model.isSavingProfile)
        // Sans réponse sûre, la demande reste en attente : elle se montre et ferme la saisie.
        api.onSend = nil; api.sendFailure = .unavailable; model.draft.contactPhone = "0765432"
        #expect(await model.saveProfileAfterConfirmation() == false)
        #expect(box.value != nil && model.pendingAwaitsReview && !model.acceptsInput && !model.canMutate)
    }

    @Test func rereadingAConcurrentProfileEditKeepsTheDraftButNeverRebasesItsVersion() async {
        let api = ProfileAPIStub()
        let editing = ProfileFixture.workspace(api: api)
        await editing.load()
        editing.draft.contactPhone = "0791112233"
        api.profileValue = ProfileFixture.profile(version: 2, phone: "0794445566")
        await editing.load()
        #expect(editing.hasProfileConflict && editing.needsReload && !editing.canSaveProfile)
        #expect(editing.profile?.version == 1 && editing.draft.contactPhone == "0791112233")
        #expect(await editing.saveProfileAfterConfirmation() == false)
        #expect(api.commands.isEmpty)
        // Repeated retries cannot erase the conflict or authorize an overwrite.
        await editing.load()
        #expect(editing.hasProfileConflict && editing.profile?.version == 1)
        // Only the explicit reload discards the local draft and accepts version 2.
        await editing.load(preserveDraft: false)
        #expect(!editing.hasProfileConflict && editing.canMutate && !editing.hasEdits)
        #expect(editing.profile?.version == 2 && editing.draft.contactPhone == "0794445566")
    }

    @Test func rereadingAnUnrelatedProfileEditPreservesBothChanges() async {
        let api = ProfileAPIStub(), box = ConfigurationOutboxStub()
        let model = ProfileFixture.workspace(api: api, box: box)
        await model.load()
        model.draft.contactPhone = "0791112233"
        api.profileValue = ProfileFixture.profile(version: 2, email: "corrige@example.invalid")
        await model.load()
        #expect(!model.hasProfileConflict && model.canSaveProfile)
        #expect(model.draft.contactPhone == "0791112233" && model.draft.contactEmail == "corrige@example.invalid")
        #expect(await model.saveProfileAfterConfirmation())
        #expect(api.commands.last?.resourceVersion == 2)
        #expect(api.profileValue.contactPhone == "0791112233" && api.profileValue.contactEmail == "corrige@example.invalid")
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
        #expect(await model.saveOnboarding(step: .review, skipping: ["PHOTO", "NOTIFICATIONS", "DEVICE"]))
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
    @Test func countriesCarryTheTwoLetterCodesTheServerExpects() {
        let countries = SchoolProfileCountry.all
        let codes = Set(countries.map(\.code))
        #expect(codes.contains("CH") && codes.count == countries.count)
        let malformed = countries.filter { $0.name.isEmpty || $0.code.range(of: "^[A-Z]{2}$", options: .regularExpression) == nil }
        #expect(malformed.isEmpty)
        var address = SchoolPostalAddress(line1: "Rue des Exemples 12", line2: nil, postalCode: "2053", locality: "Cernier", countryCode: "")
        #expect(!address.isValid)
        address.countryCode = "CH"
        #expect(address.isValid)
    }
    @Test func staffWelcomeResumeRequiresAnUnfinishedResponseForTheCurrentAccount() async {
        let api = ProfileAPIStub(), scope = ConfigurationFixture.scope()
        api.onboardingValue = ProfileFixture.onboarding(kind: .staff)
        let pending = await SchoolOnboardingPrompt.isPending(api: api, scope: scope, kind: .staff)
        #expect(pending && api.commands.isEmpty)
        api.onboardingValue = ProfileFixture.onboarding(status: "COMPLETED", kind: .staff)
        let completed = await SchoolOnboardingPrompt.isPending(api: api, scope: scope, kind: .staff)
        #expect(!completed)
        api.onboardingValue = ProfileFixture.onboarding(kind: .student)
        let wrongKind = await SchoolOnboardingPrompt.isPending(api: api, scope: scope, kind: .staff)
        #expect(!wrongKind)
        api.onboardingValue = ProfileFixture.onboarding(kind: .staff, membershipID: UUID())
        let otherMembership = await SchoolOnboardingPrompt.isPending(api: api, scope: scope, kind: .staff)
        #expect(!otherMembership)
        api.onboardingFailure = .unavailable
        let unavailable = await SchoolOnboardingPrompt.isPending(api: api, scope: scope, kind: .staff)
        #expect(!unavailable && api.commands.isEmpty)
    }
}

@MainActor
final class ProfileAPIStub: SchoolProfileAPI {
    var profileValue = ProfileFixture.profile()
    var policyValues = [ProfileFixture.policy()]
    var noticeValue = ProfileFixture.notice()
    var onboardingValue = ProfileFixture.onboarding()
    var onboardingFailure: SchoolProfileFailure?
    var firstPage: SchoolPage<SchoolProfilePolicy>?
    var readFailure: SchoolProfileFailure?
    var sendFailure: SchoolProfileFailure?
    var receipt: SchoolOperationReceipt?
    var schoolHandler: (() async -> SchoolDetails)?
    /// Appelé au début d’un envoi, pour lire l’état du modèle pendant qu’il est en cours.
    var onSend: (() -> Void)?
    var commands: [PendingSchoolCommand] = []
    var cursors: [String?] = []
    var noticeRequests: [UUID?] = []
    var operationRequests: [UUID] = []
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
    func onboarding(schoolID: UUID, kind: SchoolOnboardingKind) async throws -> SchoolOnboarding {
        if let onboardingFailure { throw onboardingFailure }
        return onboardingValue
    }
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt {
        operationRequests.append(id)
        guard let receipt else { throw SchoolProfileFailure.operationUnknown }; return receipt
    }
    func send(_ command: PendingSchoolCommand) async throws -> SchoolProfileResult {
        commands.append(command)
        onSend?()
        if let sendFailure { throw sendFailure }
        switch command.kind {
        case .updateProfile:
            // Comme le serveur : chaque champ transmis remplace la valeur, null l’efface, un champ absent est conservé.
            let body = try JSONDecoder().decode([String: SchoolProfileValue].self, from: command.body)
            func text(_ field: SchoolProfileField, _ current: String?) -> String? {
                guard let sent = body[field.rawValue] else { return current }
                if case .text(let value) = sent { return value }
                return nil
            }
            var address = profileValue.postalAddress
            if let sent = body[SchoolProfileField.postalAddress.rawValue] {
                if case .address(let value) = sent { address = value } else { address = nil }
            }
            profileValue = ProfileFixture.profile(version: command.resourceVersion + 1,
                firstName: text(.firstName, profileValue.firstName), lastName: text(.lastName, profileValue.lastName),
                email: text(.contactEmail, profileValue.contactEmail), phone: text(.contactPhone, profileValue.contactPhone),
                birthDate: text(.birthDate, profileValue.birthDate), address: address)
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
        email: String? = "alice@example.invalid", phone: String? = nil, birthDate: String? = nil,
        address: SchoolPostalAddress? = nil) -> SchoolAdministrativeProfile {
        .init(id: profileID, schoolId: ConfigurationFixture.schoolID, version: version, learnerId: learnerID,
            firstName: firstName, lastName: lastName, birthDate: birthDate, postalAddress: address, contactEmail: email,
            contactPhone: phone, profilePhotoDocumentId: nil, updatedAt: ConfigurationFixture.timestamp,
            enteredByMembershipId: ConfigurationFixture.membershipID, entrySource: "SELF", policyVersionId: policyID)
    }
    /// `fields` restreint la politique à certains champs ; sans lui, elle cite prénom, nom, e-mail et téléphone.
    static func policy(id: UUID = policyID, status: String = "PUBLISHED", version: Int = 2,
        fields: Set<SchoolProfileField>? = nil) -> SchoolProfilePolicy {
        let rules = policyDraft().selectedRules.filter { rule in fields?.contains(rule.field) ?? true }
        return .init(id: id, schoolId: ConfigurationFixture.schoolID, version: version, status: status, effectiveFrom: "2020-01-01T00:00:00Z",
            fields: rules, noticeVersionId: noticeID, approvedByMembershipId: status == "DRAFT" ? nil : ConfigurationFixture.membershipID)
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
    static func onboarding(version: Int = 1, status: String = "IN_PROGRESS", step: SchoolOnboardingStep = .identity,
        kind: SchoolOnboardingKind = .student, membershipID: UUID = ConfigurationFixture.membershipID) -> SchoolOnboarding {
        .init(id: onboardingID, schoolId: ConfigurationFixture.schoolID, version: version, personId: ConfigurationFixture.personID,
            membershipId: membershipID, kind: kind, status: status, currentStep: step,
            skippedOptionalSteps: [], policyVersionId: policyID, lastSavedAt: ConfigurationFixture.timestamp,
            pendingActions: step == .review ? [] : [.init(code: "ONBOARDING_REVIEW_REQUIRED", message: "Relis ton arrivée.", field: nil, purpose: nil, resourceId: nil, destinationKey: "PROFILE")],
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
