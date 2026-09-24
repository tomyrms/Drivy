import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolConfigurationWorkspaceTests {
    @Test func loadingNeverApprovesTextsOrActivatesTheSchool() async {
        let api = ConfigurationAPIStub()
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(api.commands.isEmpty)
        #expect(!model.canActivate)
        #expect(model.policyContactEmail == api.schoolValue.contactEmail)
        #expect(model.noticeText.isEmpty)
        #expect(model.retentionText.isEmpty)
        await model.activateAfterReview()
        #expect(api.commands.isEmpty)
    }

    @Test func policyAdoptionSendsExactlyTheReviewedTextsAndRequiredContact() async throws {
        let api = ConfigurationAPIStub()
        let outbox = ConfigurationOutboxStub()
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: outbox)
        await model.load()
        model.noticeText = "Texte d’information rédigé par l’école.\nSeconde ligne conservée."
        model.retentionText = "Texte de conservation explicitement relu."
        await model.adoptPolicyAfterReview()
        let command = try #require(api.commands.first)
        let body = try JSONDecoder().decode(SchoolDataPolicyCommand.self, from: command.body)
        #expect(body.noticeText == model.noticeText)
        #expect(body.retentionText == model.retentionText)
        #expect(body.contactEmail == api.schoolValue.contactEmail)
        #expect(body.reviewAcknowledged)
        #expect(command.kind == .saveDataPolicy)
        #expect(outbox.value == nil)
        #expect(model.policy?.status == "APPROVED")
    }

    @Test func uncertainRetryKeepsOperationPayloadVersionAndDurabilityBarrier() async throws {
        let api = ConfigurationAPIStub()
        let outbox = ConfigurationOutboxStub()
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: outbox)
        await model.load()
        model.name = "Nom confirmé"
        api.sendFailure = .unavailable
        await model.saveIdentityAfterConfirmation()
        let original = try #require(outbox.value)
        #expect(model.pending == original)
        #expect(!model.mayEdit)
        model.name = "Ce changement local ne doit pas réécrire la demande"
        api.sendFailure = nil
        await model.retryPending()
        #expect(api.commands == [original, original])
        #expect(outbox.saves == [original, original, original])
        #expect(model.name == "Nom confirmé")
        #expect(outbox.value == nil)
    }

    @Test func freshBusinessConflictAllowsReloadAndNewExplicitConfirmation() async throws {
        let api = ConfigurationAPIStub()
        let outbox = ConfigurationOutboxStub()
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: outbox)
        await model.load()
        model.name = "Correction conservée"
        api.sendFailure = .conflict
        await model.saveIdentityAfterConfirmation()
        let rejected = try #require(api.commands.first)
        #expect(outbox.value == nil)
        #expect(model.needsReload)
        #expect(!model.mayEdit)
        api.schoolValue = ConfigurationFixture.school(version: 2)
        await model.load()
        #expect(model.name == "Correction conservée")
        api.sendFailure = nil
        await model.saveIdentityAfterConfirmation()
        let confirmed = try #require(api.commands.last)
        #expect(confirmed.id != rejected.id)
        #expect(confirmed.resourceVersion == 2)
        #expect(model.school?.version == 3)
    }

    @Test func aConflictAfterRelaunchCannotDiscardTheUncertainCommand() async throws {
        let pending = try ConfigurationFixture.command()
        let api = ConfigurationAPIStub()
        api.sendFailure = .conflict
        let outbox = ConfigurationOutboxStub(value: pending)
        let model = SchoolConfigurationWorkspace(scope: pending.scope, api: api, outbox: outbox)
        await model.load()
        await model.retryPending()
        #expect(outbox.value == pending)
        #expect(model.pending == pending)
        #expect(model.pendingRequiresReview)
        #expect(!model.canRetryPending)
        #expect(outbox.removals.isEmpty)
    }

    @Test func changedAccessEpochPermitsReceiptVerificationButNeverResending() async throws {
        let pending = try ConfigurationFixture.command()
        let api = ConfigurationAPIStub()
        api.operationValue = ConfigurationFixture.receipt(pending)
        let outbox = ConfigurationOutboxStub(value: pending)
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(epoch: 2), api: api, outbox: outbox)
        await model.load()
        #expect(model.pending == pending)
        #expect(!model.canRetryPending)
        await model.retryPending()
        #expect(api.commands.isEmpty)
        await model.verifyPending()
        #expect(api.operationQueries == [pending.id])
        #expect(api.commands.isEmpty)
        #expect(outbox.value == nil)
        #expect(model.pending == nil)
    }

    @Test func absentOrMismatchedReceiptNeverMeansNoEffect() async throws {
        let pending = try ConfigurationFixture.command()
        let api = ConfigurationAPIStub()
        let outbox = ConfigurationOutboxStub(value: pending)
        let model = SchoolConfigurationWorkspace(scope: pending.scope, api: api, outbox: outbox)
        await model.load()
        await model.verifyPending()
        #expect(outbox.value == pending)
        #expect(api.commands.isEmpty)
        api.operationValue = SchoolOperationReceipt(operationId: UUID(), commandType: "UPDATE_SCHOOL",
            resourceType: "School", resourceId: pending.scope.schoolID, committedAt: ConfigurationFixture.timestamp, resourceVersion: 2)
        await model.verifyPending()
        #expect(outbox.value == pending)
        #expect(model.errorMessage == SchoolConfigurationFailure.invalidResponse.localizedDescription)
    }

    @Test func expiredAccessCannotEraseAnUncertainCommit() async throws {
        let pending = try ConfigurationFixture.command()
        let api = ConfigurationAPIStub()
        api.sendFailure = .unauthorized
        let outbox = ConfigurationOutboxStub(value: pending)
        let model = SchoolConfigurationWorkspace(scope: pending.scope, api: api, outbox: outbox)
        await model.load()
        await model.retryPending()
        #expect(outbox.value == pending)
        #expect(model.accessFailure == .unauthorized)
        #expect(outbox.removals.isEmpty)
    }

    @Test func unavailableDurableStoragePreventsFirstSendAndRetry() async throws {
        let api = ConfigurationAPIStub()
        let outbox = ConfigurationOutboxStub()
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: outbox)
        await model.load()
        outbox.failSave = true
        model.name = "Nouveau nom"
        await model.saveIdentityAfterConfirmation()
        #expect(api.commands.isEmpty)
        let pending = try ConfigurationFixture.command()
        outbox.value = pending
        let restored = SchoolConfigurationWorkspace(scope: pending.scope, api: api, outbox: outbox)
        await restored.load()
        await restored.retryPending()
        #expect(api.commands.isEmpty)
        #expect(outbox.value == pending)
    }

    @Test func closingTheScreenDiscardsLateProjectionButClearsConfirmedOutbox() async throws {
        let api = ConfigurationAPIStub()
        let outbox = ConfigurationOutboxStub()
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: outbox)
        await model.load()
        model.name = "Nouveau nom"
        let gate = ConfigurationResponse()
        api.sendHandler = { _ in try await gate.value() }
        let sending = Task { await model.saveIdentityAfterConfirmation() }
        await gate.waitUntilRequested()
        model.invalidate()
        gate.succeed(.school(ConfigurationFixture.school(version: 2, name: "Nouveau nom")))
        await sending.value
        #expect(model.school == nil)
        #expect(model.name.isEmpty)
        #expect(model.policy == nil)
        #expect(outbox.value == nil)
    }

    @Test func activationRequiresServerReadinessAdoptedPolicyAndNoUnconfirmedEdits() async throws {
        let api = ConfigurationAPIStub()
        api.policyValue = ConfigurationFixture.policy(approved: true)
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(model.canActivate)
        model.noticeText += " Modification non adoptée."
        #expect(!model.canActivate)
        await model.activateAfterReview()
        #expect(api.commands.isEmpty)
        model.noticeText = api.policyValue.noticeText
        await model.activateAfterReview()
        let command = try #require(api.commands.first)
        let body = try JSONDecoder().decode(SchoolActivationCommand.self, from: command.body)
        #expect(body.reviewAcknowledged)
        #expect(body.expectedConfigurationVersion == 1)
        #expect(command.resourceVersion == 1)
        #expect(model.school?.status == "ACTIVE")
    }
}

@MainActor
final class ConfigurationOutboxStub: SchoolCommandOutbox {
    var value: PendingSchoolCommand?
    var saves: [PendingSchoolCommand] = []
    var removals: [PendingSchoolCommand] = []
    var failSave = false
    init(value: PendingSchoolCommand? = nil) { self.value = value }
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { value }
    func save(_ command: PendingSchoolCommand) throws {
        if failSave { throw SchoolConfigurationFailure.storage }
        if let value, value != command { throw SchoolConfigurationFailure.pendingCommand }
        saves.append(command)
        value = command
    }
    func remove(_ command: PendingSchoolCommand) throws {
        guard value == command else { throw SchoolConfigurationFailure.storage }
        removals.append(command)
        value = nil
    }
}

@MainActor
final class ConfigurationAPIStub: SchoolConfigurationAPI {
    var schoolValue = ConfigurationFixture.school()
    var policyValue = ConfigurationFixture.policy()
    var sendFailure: SchoolConfigurationFailure?
    var sendHandler: ((PendingSchoolCommand) async throws -> SchoolCommandResult)?
    var operationValue: SchoolOperationReceipt?
    var commands: [PendingSchoolCommand] = []
    var operationQueries: [UUID] = []
    func school(id: UUID) async throws -> SchoolDetails { schoolValue }
    func setup(schoolID: UUID) async throws -> SchoolSetup { ConfigurationFixture.setup() }
    func readiness(schoolID: UUID) async throws -> SchoolReadiness {
        ConfigurationFixture.readiness(version: schoolValue.configurationVersion, ready: policyValue.status == "APPROVED")
    }
    func dataPolicy(schoolID: UUID) async throws -> SchoolDataPolicy { policyValue }
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt {
        operationQueries.append(id)
        guard let operationValue else { throw SchoolConfigurationFailure.operationUnknown }
        return operationValue
    }
    func send(_ command: PendingSchoolCommand) async throws -> SchoolCommandResult {
        commands.append(command)
        if let sendHandler { return try await sendHandler(command) }
        if let sendFailure { throw sendFailure }
        switch command.kind {
        case .updateSchool:
            let body = try JSONDecoder().decode(SchoolIdentityCommand.self, from: command.body)
            schoolValue = ConfigurationFixture.school(version: command.resourceVersion + 1, name: body.name)
            return .school(schoolValue)
        case .activate:
            schoolValue = ConfigurationFixture.school(version: command.resourceVersion + 1, status: "ACTIVE")
            return .school(schoolValue)
        case .saveDataPolicy:
            let body = try JSONDecoder().decode(SchoolDataPolicyCommand.self, from: command.body)
            policyValue = SchoolDataPolicy(id: command.scope.schoolID, schoolId: command.scope.schoolID,
                version: command.resourceVersion + 1, status: "APPROVED", noticeText: body.noticeText,
                retentionText: body.retentionText, contactEmail: body.contactEmail,
                approvedAt: ConfigurationFixture.timestamp, approvedByMembershipId: command.scope.membershipID)
            return .dataPolicy(policyValue)
        case .saveSetup: return .setup(ConfigurationFixture.setup(version: command.resourceVersion + 1))
        }
    }
}

@MainActor
private final class ConfigurationResponse {
    private var continuation: CheckedContinuation<SchoolCommandResult, any Error>?
    private var requested: CheckedContinuation<Void, Never>?
    func value() async throws -> SchoolCommandResult {
        try await withCheckedThrowingContinuation {
            continuation = $0
            requested?.resume(); requested = nil
        }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func succeed(_ value: SchoolCommandResult) { continuation?.resume(returning: value); continuation = nil }
}

enum ConfigurationFixture {
    static let schoolID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    static let personID = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!
    static let membershipID = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
    static let timestamp = "2026-09-24T15:00:00Z"
    static func scope(epoch: Int = 1) -> SchoolCommandScope {
        .init(personID: personID, schoolID: schoolID, membershipID: membershipID, accessEpoch: epoch, apiBaseURL: "https://api.example.invalid")
    }
    static func school(version: Int = 1, name: String = "École de test", status: String = "DRAFT") -> SchoolDetails {
        .init(id: schoolID, schoolId: schoolID, version: version, name: name, timeZone: "Europe/Zurich", status: status,
            contactEmail: "ecole@example.invalid", contactPhone: nil, logoAssetId: nil,
            modules: .init(gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false), configurationVersion: version)
    }
    static func policy(approved: Bool = false) -> SchoolDataPolicy {
        .init(id: schoolID, schoolId: schoolID, version: 1, status: approved ? "APPROVED" : "DRAFT",
            noticeText: approved ? "Information rédigée et adoptée." : "", retentionText: approved ? "Conservation définie et adoptée." : "",
            contactEmail: approved ? "ecole@example.invalid" : nil, approvedAt: approved ? timestamp : nil,
            approvedByMembershipId: approved ? membershipID : nil)
    }
    static func readiness(version: Int = 1, ready: Bool = true) -> SchoolReadiness {
        let blocker = SchoolActionBlocker(code: "SCHOOL_NOT_ACTIVE", message: "École à activer", field: nil, purpose: nil, resourceId: nil, destinationKey: nil)
        return .init(schoolId: schoolID, configurationVersion: version, computedAt: timestamp,
            capabilities: ["CAN_USE_WORKSPACE", "CAN_PLAN_LESSON", "CAN_CAPTURE", "CAN_PUBLISH_COURSE"].map {
                .init(capability: $0, ready: false, blockers: [blocker])
            }, activationReady: ready, activationBlockers: ready ? [] : [SchoolActionBlocker(code: "POLICY_REVIEW_REQUIRED",
                message: "Les textes d’information et de conservation doivent être adoptés.", field: nil, purpose: nil, resourceId: nil, destinationKey: "DATA")])
    }
    static func setup(version: Int = 1) -> SchoolSetup {
        .init(id: schoolID, schoolId: schoolID, version: version, status: "IN_PROGRESS", currentStep: "IDENTITY",
            completedSteps: [], lastSavedAt: timestamp, configuredByMembershipId: membershipID, readiness: readiness())
    }
    static func command() throws -> PendingSchoolCommand {
        let id = UUID()
        return .init(id: id, scope: scope(), kind: .updateSchool, resourceVersion: 1, createdAt: Date(),
            body: try JSONEncoder().encode(SchoolIdentityCommand(operationId: id, name: "Nom en attente", timeZone: "Europe/Zurich",
                contactEmail: "ecole@example.invalid", contactPhone: nil, impactConfirmed: true)))
    }
    static func receipt(_ command: PendingSchoolCommand) -> SchoolOperationReceipt {
        .init(operationId: command.id, commandType: "UPDATE_SCHOOL", resourceType: "School", resourceId: command.scope.schoolID,
            committedAt: timestamp, resourceVersion: command.resourceVersion + 1)
    }
}
