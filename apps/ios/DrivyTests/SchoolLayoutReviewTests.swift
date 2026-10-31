import Foundation
import Testing
@testable import Drivy

struct SchoolCoursePaymentHistoryTests {
    @Test func historyKeepsVoidedEntriesAndDistinctEqualPaymentsInDateOrder() {
        let first = payment("2026-09-20T10:00:00Z"), second = payment("2026-09-21T10:00:00Z")
        let voided = payment("2026-09-22T10:00:00Z", voidedAt: "2026-09-23T10:00:00Z", reason: "Erreur de saisie")
        let result = SchoolCoursePaymentHistoryRules.ordered([first, voided, second])
        #expect(result.map(\.id) == [voided.id, second.id, first.id])
        #expect(result.map(\.amountCents) == [5000, 5000, 5000])
        #expect(result.first?.voidedAt == voided.voidedAt)
        #expect(first.id != second.id)
    }

    @Test func unknownDatesAndAbsentReasonsDoNotProduceInventedMetadata() {
        let known = payment("2026-09-20T10:00:00Z"), unknown = payment("")
        #expect(SchoolCoursePaymentHistoryRules.ordered([unknown, known]).map(\.id) == [known.id, unknown.id])
        #expect(SchoolCoursePaymentHistoryRules.voidReason(unknown) == nil)
        #expect(SchoolCoursePaymentHistoryRules.voidReason(payment("", voidedAt: "", reason: " \n ")) == nil)
        #expect(SchoolCoursePaymentHistoryRules.voidReason(payment("", voidedAt: "", reason: " Motif confirmé ")) == "Motif confirmé")
    }

    private func payment(_ date: String, voidedAt: String? = nil, reason: String? = nil) -> SchoolCoursePayment {
        .init(id: UUID(), amountCents: 5000, recordedAt: date, note: nil, voidedAt: voidedAt, voidReason: reason)
    }
}

struct SchoolInvitationFeedbackPlacementTests {
    @Test func twoColumnsKeepGlobalErrorsInTheListAndSelectedOperationsInTheirDetail() {
        let selected = UUID(), another = UUID()
        let route = SchoolInvitationFeedbackPlacement(visibleDetailID: selected, listIsVisible: true)
        #expect(route.reading == .list)
        #expect(route.operation(for: selected) == .detail(selected))
        #expect(route.operation(for: another) == .list)
        #expect(route.operation(for: nil) == .list)
    }

    @Test func compactAndBackNavigationKeepExactlyOneDestinationWithoutChangingTheOperationTarget() {
        let selected = UUID(), another = UUID()
        let detail = SchoolInvitationFeedbackPlacement(visibleDetailID: selected, listIsVisible: false)
        #expect(detail.reading == .detail(selected))
        #expect(detail.operation(for: selected) == .detail(selected))
        #expect(detail.operation(for: another) == .list)
        let returned = SchoolInvitationFeedbackPlacement(visibleDetailID: nil, listIsVisible: true)
        #expect(returned.reading == .list && returned.operation(for: selected) == .list)
        let changed = SchoolInvitationFeedbackPlacement(visibleDetailID: another, listIsVisible: true)
        #expect(changed.operation(for: selected) == .list)
    }
}

@MainActor
struct SchoolInvitationFeedbackWorkspaceTests {
    @Test func failedRereadDoesNotOverwriteTheOperationOrAttachItToAnotherSelection() async throws {
        let api = InvitationAPIStub()
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        let target = try #require(model.invitations.first)
        model.selectedID = target.id
        api.sendFailure = .unavailable
        #expect(await model.resendAfterConfirmation(target) == false)
        let operation = try #require(model.pending?.id)
        #expect(model.operationInvitationID == target.id)
        model.selectedID = UUID()
        api.listHandler = { _ in throw SchoolInvitationFailure.invalidResponse }
        await model.load()
        #expect(model.pending?.id == operation)
        #expect(model.operationErrorMessage == SchoolInvitationFailure.unavailable.localizedDescription)
        #expect(model.readErrorMessage == SchoolInvitationFailure.invalidResponse.localizedDescription)
        #expect(model.operationInvitationID == target.id)
        api.listHandler = nil
        await model.load()
        #expect(model.readErrorMessage == nil && model.operationErrorMessage != nil)
        #expect(model.pending?.id == operation)
    }

    @Test func confirmedMutationKeepsItsTargetWhenTheFollowingReadFails() async throws {
        let api = InvitationAPIStub()
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        let target = try #require(model.invitations.first)
        api.sendHandler = { command in
            let confirmed = InvitationFixture.invitation(id: target.id, version: command.resourceVersion + 1, status: .revoked)
            api.items = [confirmed]
            api.listHandler = { _ in throw SchoolInvitationFailure.unavailable }
            return confirmed
        }
        #expect(await model.revokeAfterConfirmation(target, reason: "Exemple") == true)
        #expect(model.successMessage != nil && model.successInvitationID == target.id)
        #expect(model.readErrorMessage != nil && model.pending == nil)
        model.invalidate()
        #expect(model.successMessage == nil && model.successInvitationID == nil)
        #expect(model.operationErrorMessage == nil && model.readErrorMessage == nil)
    }
}
