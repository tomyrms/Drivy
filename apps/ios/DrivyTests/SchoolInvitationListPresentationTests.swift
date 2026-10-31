import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolInvitationListPresentationTests {
    private let now = SchoolInvitation.date("2026-10-01T14:00:00Z")!

    @Test func searchUsesOnlyAuthorizedLabelsAndTheNonSecretReference() {
        var code = InvitationFixture.codeInvitation(code: "Q7XZ9ABC")
        code.trainingCategoryCode = "B"
        #expect(SchoolInvitationListPresentation.matches(code, training: "Permis B", reference: "A123", query: " ELEVE  permis b "))
        #expect(SchoolInvitationListPresentation.matches(code, training: "Permis B", reference: "A123", query: "Réf. a123"))
        #expect(!SchoolInvitationListPresentation.matches(code, training: "Permis B", reference: "A123", query: "Q7XZ9ABC"))
        let email = InvitationFixture.invitation(email: "a***@example.invalid", roles: [.instructor])
        #expect(SchoolInvitationListPresentation.matches(email, training: nil, reference: "B234", query: "MONITEUR a***"))
        #expect(!SchoolInvitationListPresentation.matches(email, training: nil, reference: "B234", query: "alice@example.invalid"))
    }

    @Test func expiryBoundaryDoesNotInventAcceptanceOrRevocation() throws {
        let pending = InvitationFixture.codeInvitation()
        let deadline = try #require(SchoolInvitation.date(pending.expiresAt))
        #expect(SchoolInvitationListPresentation.status(pending, now: deadline.addingTimeInterval(-0.001)) == .pending)
        #expect(SchoolInvitationListPresentation.status(pending, now: deadline) == .expired)
        #expect(SchoolInvitationListPresentation.statusLabel(pending, now: deadline) == "Échéance passée")
        #expect(SchoolInvitationListPresentation.activeDeadline(pending, now: deadline, timeZone: "Europe/Zurich") == nil)
        #expect(SchoolInvitationListFilter.expired.includes(SchoolInvitationListPresentation.status(pending, now: deadline)))
        for status in [SchoolInvitationStatus.accepted, .revoked, .expired] {
            let confirmed = InvitationFixture.codeInvitation(status: status)
            #expect(SchoolInvitationListPresentation.status(confirmed, now: now) == status)
            #expect(SchoolInvitationListPresentation.status(confirmed, now: deadline.addingTimeInterval(1)) == status)
            #expect(SchoolInvitationListPresentation.activeDeadline(confirmed, now: now, timeZone: "Europe/Zurich") == nil)
        }
    }

    @Test func deadlineUsesTheSchoolTimeZoneAndNeverInventsAMissingValue() {
        let invitation = InvitationFixture.invitation()
        #expect(SchoolInvitationListPresentation.deadline(invitation, timeZone: "Europe/Zurich").contains("16:30"))
        #expect(SchoolInvitationListPresentation.deadline(invitation, timeZone: "America/Los_Angeles").contains("07:30"))
        let winter = SchoolInvitation(id: invitation.id, schoolId: invitation.schoolId, version: 1, maskedEmail: invitation.maskedEmail,
            roles: [.learner], status: .pending, expiresAt: "2026-12-01T14:30:00Z")
        #expect(SchoolInvitationListPresentation.deadline(winter, timeZone: "Europe/Zurich").contains("15:30"))
        #expect(SchoolInvitationListPresentation.deadline(invitation, timeZone: nil) == "Fuseau de l’école indisponible")
        #expect(SchoolInvitationListPresentation.deadline(invitation, timeZone: "Missing/Zone") == "Fuseau de l’école indisponible")
        let missing = SchoolInvitation(id: invitation.id, schoolId: invitation.schoolId, version: 1, maskedEmail: nil,
            roles: [.learner], status: .pending, expiresAt: "", delivery: .code)
        #expect(SchoolInvitationListPresentation.activeDeadline(missing, now: now, timeZone: "Europe/Zurich") == "Échéance indisponible")
        #expect(SchoolInvitationListPresentation.statusLabel(missing, now: now) == "En attente")
    }

    @Test func referencesDistinguishIdenticalCodesAndOnlyExtendOnAnActualCollision() throws {
        let a = InvitationFixture.codeInvitation(id: UUID(uuidString: "40000000-0000-4000-8000-0000000A1234")!)
        let b = InvitationFixture.codeInvitation(id: UUID(uuidString: "40000000-0000-4000-8000-0000000B1234")!)
        let c = InvitationFixture.codeInvitation(id: UUID(uuidString: "40000000-0000-4000-8000-000000005678")!)
        let initial = SchoolInvitationListPresentation.references([a, c], previous: [:])
        let paginated = SchoolInvitationListPresentation.references([a, b, c], previous: initial)
        #expect(initial[a.id] == "1234" && paginated[a.id] == "A1234" && paginated[b.id] == "B1234")
        #expect(paginated[c.id] == initial[c.id])
        let renewed = InvitationFixture.codeInvitation(id: a.id, version: 2, code: "Q7XZ9ABC")
        #expect(SchoolInvitationListPresentation.references([c, b, renewed], previous: paginated) == paginated)
        #expect(SchoolInvitationListPresentation.references([renewed], previous: paginated)[a.id] == paginated[a.id])
        #expect(Set(paginated.values).count == 3)
        #expect(try #require(paginated[a.id]) != renewed.code)
    }

    @Test func filteringDoesNotFetchPagesOrChangeTheSelectedInvitation() async {
        let first = InvitationFixture.codeInvitation()
        var second = InvitationFixture.codeInvitation(id: UUID())
        second.trainingCategoryCode = "A"
        let api = InvitationAPIStub()
        let next = second
        api.listHandler = { cursor in cursor == nil ? .init(items: [first], nextCursor: "page-two")
            : .init(items: [next], nextCursor: nil) }
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        model.selectedID = first.id
        #expect(model.matchingInvitations(query: "permis a", filter: .pending, now: now).isEmpty)
        #expect(api.queries.count == 1 && model.nextCursor == "page-two")
        #expect(model.selectedInvitation?.id == first.id)
        await model.loadMore()
        #expect(model.matchingInvitations(query: "permis a", filter: .pending, now: now).map(\.id) == [second.id])
        #expect(api.queries.count == 2 && model.nextCursor == nil)
        #expect(model.selectedID == first.id && api.commands.isEmpty)
        #expect(model.invitations.allSatisfy { $0.code == nil })
    }

    @Test func refreshRevalidatesOnlyTheLoadedWindowAndKeepsItsSelectedIdentity() async {
        let first = InvitationFixture.invitation()
        let second = InvitationFixture.invitation(id: UUID())
        let api = InvitationAPIStub()
        api.listHandler = { cursor in cursor == nil ? .init(items: [first], nextCursor: "page-two")
            : .init(items: [second], nextCursor: "page-three") }
        let model = InvitationFixture.workspace(api: api)
        await model.load(); await model.loadMore()
        model.selectedID = second.id
        let reference = model.reference(second)
        let accepted = InvitationFixture.invitation(id: second.id, version: 2, status: .accepted)
        api.listHandler = { cursor in cursor == nil ? .init(items: [first], nextCursor: "new-page-two")
            : .init(items: [accepted], nextCursor: "new-page-three") }
        await model.load()
        #expect(api.queries == [nil, "page-two", nil, "new-page-two"])
        #expect(model.nextCursor == "new-page-three" && model.selectedID == second.id)
        #expect(model.selectedInvitation == accepted && model.reference(accepted) == reference)
        #expect(model.matchingInvitations(query: "", filter: .accepted, now: now).map(\.id) == [second.id])
        #expect(model.matchingInvitations(query: "", filter: .pending, now: now).map(\.id) == [first.id])
    }

    @Test func renewedReferenceStillTargetsTheCompleteReviewedIdentifier() async throws {
        let first = InvitationFixture.codeInvitation(id: UUID(uuidString: "40000000-0000-4000-8000-0000000A1234")!)
        let second = InvitationFixture.codeInvitation(id: UUID(uuidString: "40000000-0000-4000-8000-0000000B1234")!)
        let api = InvitationAPIStub(); api.items = [first, second]
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        model.selectedID = second.id
        let reference = model.reference(second)
        #expect(await model.resendAfterConfirmation(second))
        let command = try #require(api.commands.first)
        #expect(command.resourceID == second.id && command.resourceVersion == second.version)
        #expect(model.selectedInvitation?.id == second.id)
        #expect(model.reference(try #require(model.selectedInvitation)) == reference)
        #expect(model.invitations.first { $0.id == first.id } == first)
        #expect(model.invitations.allSatisfy { $0.code == nil })
    }

    @Test func revocationOfAccessDuringTheWindowRefreshClearsSearchableDataAndReferences() async {
        let first = InvitationFixture.invitation()
        let second = InvitationFixture.invitation(id: UUID())
        let api = InvitationAPIStub()
        api.listHandler = { cursor in cursor == nil ? .init(items: [first], nextCursor: "page-two")
            : .init(items: [second], nextCursor: nil) }
        let model = InvitationFixture.workspace(api: api)
        await model.load(); await model.loadMore()
        model.selectedID = second.id
        api.listHandler = { cursor in
            if cursor != nil { throw SchoolInvitationFailure.forbidden }
            return .init(items: [first], nextCursor: "page-two")
        }
        await model.load()
        #expect(model.matchingInvitations(query: "", filter: .all, now: now).isEmpty)
        #expect(model.invitationReferences.isEmpty && model.selectedID == nil && model.nextCursor == nil)
        #expect(model.accessFailure == .forbidden && !model.mayEdit)
    }

    @Test func aLateRefreshPageCannotReplaceASecondRefresh() async {
        let first = InvitationFixture.invitation()
        let second = InvitationFixture.invitation(id: UUID())
        let api = InvitationAPIStub()
        api.listHandler = { cursor in cursor == nil ? .init(items: [first], nextCursor: "page-two")
            : .init(items: [second], nextCursor: nil) }
        let model = InvitationFixture.workspace(api: api)
        await model.load(); await model.loadMore()
        model.selectedID = second.id
        let held = InvitationListResponse()
        api.listHandler = { cursor in
            if cursor != nil { return await held.value() }
            return .init(items: [first], nextCursor: "page-two")
        }
        let oldRefresh = Task { await model.load() }
        await held.waitUntilRequested()
        #expect(model.selectedInvitation?.id == second.id)
        let revoked = InvitationFixture.invitation(id: second.id, version: 2, status: .revoked)
        api.listHandler = { cursor in cursor == nil ? .init(items: [first], nextCursor: "new-page-two")
            : .init(items: [revoked], nextCursor: nil) }
        await model.load()
        held.succeed(.init(items: [second], nextCursor: nil))
        await oldRefresh.value
        #expect(model.selectedInvitation == revoked && model.nextCursor == nil)
    }
}

@MainActor
private final class InvitationListResponse {
    private var continuation: CheckedContinuation<SchoolPage<SchoolInvitation>, Never>?
    private var requested: CheckedContinuation<Void, Never>?
    func value() async -> SchoolPage<SchoolInvitation> {
        await withCheckedContinuation { continuation = $0; requested?.resume(); requested = nil }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func succeed(_ value: SchoolPage<SchoolInvitation>) { continuation?.resume(returning: value); continuation = nil }
}
