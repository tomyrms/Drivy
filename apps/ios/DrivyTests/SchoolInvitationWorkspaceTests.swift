import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolInvitationWorkspaceTests {
    @Test func loadingDoesNotInviteAndInstructorCannotGrantStaffRoles() async {
        let api = InvitationAPIStub()
        let model = InvitationFixture.workspace(api: api, roles: ["INSTRUCTOR"])
        await model.load()
        #expect(api.commands.isEmpty)
        #expect(model.allowedRoles == [.learner])
        #expect(await model.inviteAfterConfirmation(email: "person@example.invalid", roles: [.admin]) == false)
        #expect(await model.inviteAfterConfirmation(email: "person@example.invalid", roles: [.learner, .instructor]) == false)
        #expect(api.commands.isEmpty)
        #expect(model.mayEdit)
    }

    @Test func inactiveSchoolOrLearnerRoleCannotManageInvitations() async {
        let api = InvitationAPIStub()
        api.schoolValue = ConfigurationFixture.school()
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        #expect(!model.mayEdit)
        #expect(api.queries.isEmpty)
        let learner = InvitationFixture.workspace(api: api, roles: ["LEARNER"])
        await learner.load()
        #expect(learner.accessFailure == .forbidden)
        #expect(api.queries.isEmpty)
    }

    @Test func creationRequiresConfirmationThenKeepsOnlyMaskedServerProjection() async throws {
        let api = InvitationAPIStub()
        let outbox = ConfigurationOutboxStub()
        let model = InvitationFixture.workspace(api: api, outbox: outbox)
        await model.load()
        model.email = "new@example.invalid"
        model.selectedRoles = [.admin, .instructor]
        #expect(api.commands.isEmpty)
        #expect(await model.inviteAfterConfirmation(email: model.email, roles: model.selectedRoles))
        let command = try #require(api.commands.first)
        let body = try JSONDecoder().decode(SchoolInviteCommand.self, from: command.body)
        #expect(body.email == "new@example.invalid")
        #expect(Set(body.roles) == [.admin, .instructor])
        #expect(command.resourceVersion == 0 && command.resourceID == nil)
        #expect(outbox.saves == [command, command])
        #expect(outbox.value == nil)
        #expect(model.email.isEmpty)
        #expect(model.invitations.first?.maskedEmail == "n***@example.invalid")
        #expect(model.successMessage?.contains("réception de l’e-mail n’est pas confirmée") == true)
    }

    @Test func uncertainCreationSurvivesRecreationAndRetriesIdenticalBytesAfterDurabilityBarrier() async throws {
        let api = InvitationAPIStub()
        api.sendFailure = .unavailable
        let outbox = ConfigurationOutboxStub()
        let first = InvitationFixture.workspace(api: api, outbox: outbox)
        await first.load()
        #expect(await first.inviteAfterConfirmation(email: "new@example.invalid", roles: [.learner]) == false)
        let pending = try #require(outbox.value)
        let reopened = InvitationFixture.workspace(api: api, outbox: outbox)
        await reopened.load()
        #expect(reopened.pending == pending)
        #expect(!reopened.mayEdit)
        api.sendFailure = nil
        await reopened.retryPending()
        #expect(api.commands == [pending, pending])
        #expect(outbox.saves == [pending, pending, pending])
        #expect(outbox.value == nil)
    }

    @Test func aFreshBusinessConflictAllowsCorrectionButAResumedConflictRetainsTheCommand() async throws {
        let api = InvitationAPIStub()
        api.sendFailure = .alreadyInvited
        let outbox = ConfigurationOutboxStub()
        let model = InvitationFixture.workspace(api: api, outbox: outbox)
        await model.load()
        model.email = "new@example.invalid"
        #expect(await model.inviteAfterConfirmation(email: model.email, roles: [.learner]) == false)
        #expect(outbox.value == nil && model.needsReload)
        #expect(model.email == "new@example.invalid")
        await model.load()
        api.sendFailure = .unavailable
        #expect(await model.inviteAfterConfirmation(email: model.email, roles: [.learner]) == false)
        let pending = try #require(model.pending)
        api.sendFailure = .conflict
        await model.retryPending()
        #expect(model.pending == pending && outbox.value == pending)
        #expect(model.pendingRequiresReview && !model.canRetryPending)
        await model.retryPending()
        #expect(api.commands.count == 3)
    }

    @Test func resendAndRevocationPreserveReviewedTargetVersionAndReason() async throws {
        let api = InvitationAPIStub()
        let original = InvitationFixture.invitation(status: .expired)
        api.items = [original]
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        #expect(await model.resendAfterConfirmation(original))
        let resent = try #require(model.invitations.first)
        #expect(resent.status == .pending && resent.version == 2)
        #expect(await model.revokeAfterConfirmation(resent, reason: "Adresse erronée"))
        let revoked = try #require(model.invitations.first)
        #expect(revoked.status == .revoked)
        #expect(api.commands.map(\.resourceID) == [original.id, original.id])
        #expect(api.commands.map(\.resourceVersion) == [1, 2])
        let body = try JSONDecoder().decode(SchoolRevokeInvitationCommand.self, from: api.commands[1].body)
        #expect(body.reason == "Adresse erronée")
        #expect(await model.resendAfterConfirmation(revoked) == false)
    }

    @Test func unreviewedNewVersionOrInvalidRevocationReasonCannotBeSubmitted() async {
        let api = InvitationAPIStub()
        let old = InvitationFixture.invitation()
        api.items = [InvitationFixture.invitation(version: 2)]
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        #expect(await model.resendAfterConfirmation(old) == false)
        #expect(await model.revokeAfterConfirmation(api.items[0], reason: "  ") == false)
        #expect(await model.revokeAfterConfirmation(api.items[0], reason: String(repeating: "x", count: 1001)) == false)
        #expect(api.commands.isEmpty)
    }

    @Test func changedScopeBlocksResendAndOnlyMatchingReceiptReleasesThePendingCommand() async throws {
        let command = try InvitationFixture.command()
        let outbox = ConfigurationOutboxStub(value: command)
        let api = InvitationAPIStub()
        let model = SchoolInvitationWorkspace(scope: ConfigurationFixture.scope(epoch: 2), roles: ["ADMIN"], api: api, outbox: outbox)
        await model.load()
        #expect(!model.canRetryPending && model.invitations.count == 1)
        await model.retryPending()
        #expect(api.commands.isEmpty)
        await model.verifyPending()
        #expect(outbox.value == command)
        api.receipt = InvitationFixture.receipt(command, resourceID: UUID())
        await model.verifyPending()
        #expect(outbox.value == command)
        api.receipt = InvitationFixture.receipt(command)
        await model.verifyPending()
        #expect(outbox.value == nil)
    }

    @Test func pendingConfigurationBlocksOnlyMutationsAndCanBeVerifiedWithoutWrongClientReplay() async throws {
        let command = try ConfigurationFixture.command()
        let api = InvitationAPIStub()
        let outbox = ConfigurationOutboxStub(value: command)
        let model = InvitationFixture.workspace(api: api, outbox: outbox)
        await model.load()
        #expect(model.invitations.count == 1)
        #expect(!model.mayEdit && !model.canRetryPending)
        await model.retryPending()
        #expect(api.commands.isEmpty)
        api.receipt = ConfigurationFixture.receipt(command)
        await model.verifyPending()
        #expect(outbox.value == nil && model.mayEdit)
    }

    @Test func refusalToReadAnOldConfigurationReceiptDoesNotRemoveCurrentInvitationAccess() async throws {
        let command = try ConfigurationFixture.command()
        let api = InvitationAPIStub()
        let outbox = ConfigurationOutboxStub(value: command)
        let model = InvitationFixture.workspace(api: api, roles: ["INSTRUCTOR"], outbox: outbox)
        await model.load()
        api.operationFailure = .forbidden
        await model.verifyPending()
        #expect(model.accessFailure == nil)
        #expect(model.invitations.count == 1)
        #expect(outbox.value == command)
        #expect(model.errorMessage?.contains("vérifier cette demande") == true)
        api.listHandler = { _ in throw SchoolInvitationFailure.forbidden }
        await model.verifyPending()
        #expect(model.accessFailure == .forbidden)
        #expect(model.invitations.isEmpty)
        #expect(outbox.value == command)
    }

    @Test func inaccessibleProtectedStorageBlocksWritesButNotAuthorizedConsultation() async {
        let api = InvitationAPIStub()
        let outbox = ConfigurationOutboxStub()
        outbox.failRead = true
        let model = InvitationFixture.workspace(api: api, outbox: outbox)
        await model.load()
        #expect(model.invitations.count == 1 && model.school != nil)
        #expect(!model.mayEdit && model.errorMessage != nil)
        #expect(await model.inviteAfterConfirmation(email: "new@example.invalid", roles: [.learner]) == false)
        #expect(api.commands.isEmpty && outbox.value == nil)
    }

    @Test func paginationMergesWithoutDowngradingVersionsAndRejectsCursorLoops() async {
        let api = InvitationAPIStub()
        let first = InvitationFixture.invitation(version: 3)
        let second = InvitationFixture.invitation(id: UUID())
        api.listHandler = { cursor in
            cursor == nil ? .init(items: [first], nextCursor: "page-two")
                : .init(items: [InvitationFixture.invitation(), second], nextCursor: "page-two")
        }
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        await model.loadMore()
        #expect(model.invitations == [first])
        #expect(model.needsReload)
        api.listHandler = { cursor in cursor == nil ? .init(items: [first], nextCursor: "page-two")
            : .init(items: [InvitationFixture.invitation(), second], nextCursor: nil) }
        await model.load()
        await model.loadMore()
        #expect(model.invitations == [first, second])
    }

    @Test func accessRevocationPurgesProjectionsButDoesNotDiscardAnUncertainCommand() async throws {
        let command = try InvitationFixture.command()
        let outbox = ConfigurationOutboxStub(value: command)
        let api = InvitationAPIStub()
        let model = InvitationFixture.workspace(api: api, outbox: outbox)
        await model.load()
        model.email = "private@example.invalid"
        api.sendFailure = .forbidden
        await model.retryPending()
        #expect(model.invitations.isEmpty && model.school == nil && model.email.isEmpty)
        #expect(model.accessFailure == .forbidden)
        #expect(outbox.value == command)
    }

    @Test func lateReadAfterClosureCannotRestoreSchoolData() async {
        let api = InvitationAPIStub()
        let held = InvitationResponse<SchoolPage<SchoolInvitation>>()
        api.listHandler = { _ in try await held.value() }
        let model = InvitationFixture.workspace(api: api)
        let task = Task { await model.load() }
        await held.waitUntilRequested()
        model.invalidate()
        held.succeed(.init(items: [InvitationFixture.invitation()], nextCursor: nil))
        await task.value
        #expect(model.school == nil && model.invitations.isEmpty && !model.isLoading)
    }

    @Test func aLatePageCannotUndoAConfirmedRevocation() async {
        let api = InvitationAPIStub()
        let held = InvitationResponse<SchoolPage<SchoolInvitation>>()
        api.listHandler = { cursor in
            if cursor != nil { return try await held.value() }
            return .init(items: api.items, nextCursor: "older-page")
        }
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        let original = api.items[0]
        let page = Task { await model.loadMore() }
        await held.waitUntilRequested()
        #expect(await model.revokeAfterConfirmation(original, reason: "Erreur de destinataire"))
        held.succeed(.init(items: [original], nextCursor: nil))
        await page.value
        #expect(model.invitations.first?.status == .revoked)
        #expect(model.invitations.first?.version == 2)
    }

    @Test func foreignSchoolOrStaffInvitationIsNeverShownToAnInstructor() async {
        let api = InvitationAPIStub()
        let other = SchoolInvitation(id: UUID(), schoolId: UUID(), version: 1, maskedEmail: "x***@example.invalid",
            roles: [.learner], status: .pending, expiresAt: ConfigurationFixture.timestamp)
        let model = InvitationFixture.workspace(api: api, roles: ["INSTRUCTOR"])
        for item in [other, InvitationFixture.invitation(roles: [.admin])] {
            api.items = [item]
            await model.load()
            #expect(model.invitations.isEmpty)
            #expect(!model.mayEdit)
            #expect(model.errorMessage != nil)
        }
    }

    @Test func storageFailureNeverEmitsAndConfirmedLateCommandStillClearsItsDurableRecord() async throws {
        let api = InvitationAPIStub()
        let outbox = ConfigurationOutboxStub()
        let model = InvitationFixture.workspace(api: api, outbox: outbox)
        await model.load()
        outbox.failSave = true
        #expect(await model.inviteAfterConfirmation(email: "new@example.invalid", roles: [.learner]) == false)
        #expect(api.commands.isEmpty)
        outbox.failSave = false
        await model.load()
        let held = InvitationResponse<SchoolInvitation>()
        api.sendHandler = { _ in try await held.value() }
        let task = Task { await model.inviteAfterConfirmation(email: "new@example.invalid", roles: [.learner]) }
        await held.waitUntilRequested()
        model.invalidate()
        held.succeed(InvitationFixture.invitation())
        _ = await task.value
        #expect(outbox.value == nil)
        #expect(model.invitations.isEmpty && model.school == nil)
    }
}

@MainActor
final class InvitationAPIStub: SchoolInvitationAPI {
    var schoolValue = ConfigurationFixture.school(status: "ACTIVE")
    var items = [InvitationFixture.invitation()]
    var commands: [PendingSchoolCommand] = []
    var queries: [String?] = []
    var sendFailure: SchoolInvitationFailure?
    var operationFailure: SchoolInvitationFailure?
    var receipt: SchoolOperationReceipt?
    var listHandler: ((String?) async throws -> SchoolPage<SchoolInvitation>)?
    var sendHandler: ((PendingSchoolCommand) async throws -> SchoolInvitation)?
    func school(id: UUID) async throws -> SchoolDetails { schoolValue }
    func invitations(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolInvitation> {
        queries.append(cursor)
        if let listHandler { return try await listHandler(cursor) }
        return .init(items: items, nextCursor: nil)
    }
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt {
        if let operationFailure { throw operationFailure }
        guard let receipt else { throw SchoolInvitationFailure.operationUnknown }
        return receipt
    }
    func send(_ command: PendingSchoolCommand) async throws -> SchoolInvitation {
        commands.append(command)
        if let sendHandler { return try await sendHandler(command) }
        if let sendFailure { throw sendFailure }
        let result: SchoolInvitation
        if command.kind == .createInvitation {
            let body = try JSONDecoder().decode(SchoolInviteCommand.self, from: command.body)
            result = InvitationFixture.invitation(id: UUID(), email: "n***@example.invalid", roles: body.roles)
        } else {
            result = InvitationFixture.invitation(id: command.resourceID!, version: command.resourceVersion + 1,
                status: command.kind == .revokeInvitation ? .revoked : .pending)
        }
        items.removeAll { $0.id == result.id }
        items.insert(result, at: 0)
        return result
    }
}

enum InvitationFixture {
    static let invitationID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    static func invitation(id: UUID = invitationID, version: Int = 1, email: String = "a***@example.invalid",
        roles: [SchoolInvitationRole] = [.learner], status: SchoolInvitationStatus = .pending) -> SchoolInvitation {
        .init(id: id, schoolId: ConfigurationFixture.schoolID, version: version, maskedEmail: email, roles: roles,
            status: status, expiresAt: "2026-10-01T14:30:00Z")
    }
    @MainActor static func workspace(api: InvitationAPIStub, roles: [String] = ["ADMIN"],
        outbox: ConfigurationOutboxStub = ConfigurationOutboxStub()) -> SchoolInvitationWorkspace {
        .init(scope: ConfigurationFixture.scope(), roles: roles, api: api, outbox: outbox)
    }
    static func command() throws -> PendingSchoolCommand {
        let id = UUID()
        return .init(id: id, scope: ConfigurationFixture.scope(), kind: .resendInvitation, resourceVersion: 1,
            createdAt: Date(), body: try JSONEncoder().encode(SchoolResendInvitationCommand(operationId: id)), resourceID: invitationID)
    }
    static func receipt(_ command: PendingSchoolCommand, resourceID: UUID = invitationID) -> SchoolOperationReceipt {
        .init(operationId: command.id, commandType: command.kind.operationType, resourceType: command.kind.resourceType,
            resourceId: resourceID, committedAt: ConfigurationFixture.timestamp, resourceVersion: command.resourceVersion + 1)
    }
}

@MainActor
private final class InvitationResponse<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var requested: CheckedContinuation<Void, Never>?
    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation = $0; requested?.resume(); requested = nil }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func succeed(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
}
