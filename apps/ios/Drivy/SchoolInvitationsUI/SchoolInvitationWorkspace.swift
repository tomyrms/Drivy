import Foundation
import Observation

@MainActor
@Observable
final class SchoolInvitationWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let roles: [String]
    private(set) var school: SchoolDetails?
    private(set) var invitations: [SchoolInvitation] = []
    private(set) var nextCursor: String?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isBusy = false
    private(set) var needsReload = false
    private(set) var pendingRequiresReview = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var accessFailure: SchoolInvitationFailure?
    var email = ""
    var selectedRoles: Set<SchoolInvitationRole> = [.learner]
    var selectedID: UUID?

    @ObservationIgnored private let api: any SchoolInvitationAPI
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var pageRequest = UUID()
    @ObservationIgnored private var seenCursors: Set<String> = []
    @ObservationIgnored private var storageAccessible = false
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var isInvalidated = false

    init(scope: SchoolCommandScope, roles: [String], api: any SchoolInvitationAPI,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.roles = roles; self.api = api; self.outbox = outbox
    }

    var allowedRoles: [SchoolInvitationRole] {
        if roles.contains("ADMIN") { return SchoolInvitationRole.allCases }
        return roles.contains("INSTRUCTOR") ? [.learner] : []
    }
    var mayEdit: Bool {
        hasLoaded && storageAccessible && school?.status == "ACTIVE" && !allowedRoles.isEmpty
            && !isLoading && !isBusy && !isInvalidated && !needsReload && pending == nil
    }
    var canRetryPending: Bool {
        pending?.kind.isInvitation == true && pending?.scope == scope && school?.status == "ACTIVE"
            && !pendingRequiresReview && !isBusy && !isLoading && !isInvalidated
    }
    var canVerifyPending: Bool { pending != nil && !isBusy && !isLoading && !isInvalidated }
    var draftIsValid: Bool { valid(email: email, roles: selectedRoles) }
    var selectedInvitation: SchoolInvitation? { invitations.first { $0.id == selectedID } }

    func invalidate() {
        generation = UUID(); pageRequest = UUID(); isInvalidated = true
        school = nil; invitations = []; nextCursor = nil; selectedID = nil; pending = nil
        email = ""; selectedRoles = [.learner]; errorMessage = nil; successMessage = nil
        isLoading = false; isLoadingMore = false; isBusy = false; storageAccessible = false
    }

    func load(receiptRefused: Bool = false) async {
        guard !isInvalidated, !isBusy else { return }
        guard !allowedRoles.isEmpty else { fail(SchoolInvitationFailure.forbidden); return }
        generation = UUID(); pageRequest = UUID()
        let request = generation
        isLoading = true; isLoadingMore = false; storageAccessible = false; errorMessage = nil
        needsReload = true
        var storageError: String?
        do {
            pending = try outbox.pending(for: scope)
            if pending == nil { pendingRequiresReview = false }
            storageAccessible = true
        } catch {
            // Protected command storage gates mutations, not authorized reads.
            storageError = SchoolConfigurationFailure.storage.localizedDescription
        }
        do {
            let school = try await api.school(id: scope.schoolID)
            guard request == generation else { return }
            guard school.id == scope.schoolID else { throw SchoolInvitationFailure.invalidResponse }
            self.school = school
            guard school.status == "ACTIVE" else {
                invitations = []; nextCursor = nil; selectedID = nil
                throw SchoolInvitationFailure.schoolInactive
            }
            let page = try await api.invitations(schoolID: scope.schoolID, cursor: nil)
            guard request == generation else { return }
            try validate(page)
            invitations = page.items; nextCursor = page.nextCursor; seenCursors = []
            if !invitations.contains(where: { $0.id == selectedID }) { selectedID = nil }
            hasLoaded = true; needsReload = false; isLoading = false
            errorMessage = storageError ?? (receiptRefused
                ? "Vos droits ne permettent pas de vérifier cette demande. Sa référence reste conservée." : nil)
        } catch {
            guard request == generation else { return }
            isLoading = false
            fail(error)
        }
    }

    func loadMore() async {
        guard !isInvalidated, !isLoading, !isLoadingMore, !isBusy, let cursor = nextCursor else { return }
        let request = generation
        pageRequest = UUID()
        let pageID = pageRequest
        isLoadingMore = true
        errorMessage = storageAccessible ? nil : SchoolConfigurationFailure.storage.localizedDescription
        do {
            let page = try await api.invitations(schoolID: scope.schoolID, cursor: cursor)
            guard request == generation, pageID == pageRequest else { return }
            try validate(page)
            guard page.nextCursor != cursor, page.nextCursor.map({ !seenCursors.contains($0) }) ?? true else {
                throw SchoolInvitationFailure.invalidCursor
            }
            seenCursors.insert(cursor)
            for item in page.items {
                if let index = invitations.firstIndex(where: { $0.id == item.id }) {
                    if item.version >= invitations[index].version { invitations[index] = item }
                } else { invitations.append(item) }
            }
            nextCursor = page.nextCursor; isLoadingMore = false
        } catch {
            guard request == generation, pageID == pageRequest else { return }
            isLoadingMore = false
            if error as? SchoolInvitationFailure == .invalidCursor { needsReload = true }
            fail(error)
        }
    }

    @discardableResult
    func inviteAfterConfirmation(email: String, roles: Set<SchoolInvitationRole>) async -> Bool {
        guard mayEdit, valid(email: email, roles: roles) else { return false }
        let id = UUID()
        let command = SchoolInviteCommand(operationId: id, email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            roles: SchoolInvitationRole.allCases.filter { roles.contains($0) })
        let confirmed = await prepare(command, id: id, kind: .createInvitation, resource: nil, version: 0)
        if confirmed && !isInvalidated { self.email = ""; selectedRoles = [.learner] }
        return confirmed
    }

    @discardableResult
    func resendAfterConfirmation(_ invitation: SchoolInvitation) async -> Bool {
        guard canManage(invitation) else { return false }
        let id = UUID()
        return await prepare(SchoolResendInvitationCommand(operationId: id), id: id, kind: .resendInvitation,
            resource: invitation.id, version: invitation.version)
    }

    @discardableResult
    func revokeAfterConfirmation(_ invitation: SchoolInvitation, reason: String) async -> Bool {
        guard canManage(invitation), Self.reasonIsValid(reason) else { return false }
        let id = UUID()
        return await prepare(SchoolRevokeInvitationCommand(operationId: id, reason: reason), id: id,
            kind: .revokeInvitation, resource: invitation.id, version: invitation.version)
    }

    func canManage(_ invitation: SchoolInvitation) -> Bool {
        mayEdit && invitation.schoolId == scope.schoolID && invitation.status.canBeManaged
            && invitations.contains(invitation) && Set(invitation.roles).isSubset(of: Set(allowedRoles))
    }

    func retryPending() async { _ = await transmit(firstAttempt: false) }

    func verifyPending() async {
        guard canVerifyPending, let command = pending else { return }
        let request = generation
        isBusy = true; errorMessage = nil
        do {
            let receipt = try await api.operation(schoolID: scope.schoolID, id: command.id)
            guard command.matches(receipt) else { throw SchoolInvitationFailure.invalidResponse }
            try outbox.remove(command)
            guard request == generation else { return }
            pending = nil; pendingRequiresReview = false; isBusy = false
            successMessage = "Le résultat de la demande a été confirmé."
            if command.kind == .createInvitation { email = ""; selectedRoles = [.learner] }
            await load()
        } catch {
            guard request == generation else { return }
            isBusy = false
            if error as? SchoolInvitationFailure == .forbidden {
                // AP72 permission depends on the original command type. A
                // denied G1B receipt does not itself revoke invitation access.
                await load(receiptRefused: true)
            } else { fail(error) }
        }
    }

    private func prepare<Value: Encodable>(_ value: Value, id: UUID, kind: SchoolCommandKind,
        resource: UUID?, version: Int) async -> Bool {
        guard mayEdit else { return false }
        successMessage = nil; errorMessage = nil
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let command = PendingSchoolCommand(id: id, scope: scope, kind: kind, resourceVersion: version,
                createdAt: Date(), body: try encoder.encode(value), resourceID: resource)
            try outbox.save(command)
            pending = command; pendingRequiresReview = false
        } catch {
            storageAccessible = false; fail(error); return false
        }
        return await transmit(firstAttempt: true)
    }

    private func transmit(firstAttempt: Bool) async -> Bool {
        guard canRetryPending, let command = pending else { return false }
        let request = generation
        do { try outbox.save(command) }
        catch { storageAccessible = false; fail(error); return false }
        isBusy = true; errorMessage = nil
        // An older pagination response cannot restore the pre-command version.
        pageRequest = UUID(); isLoadingMore = false
        do {
            let result = try await api.send(command)
            guard SchoolInvitationClient.valid(result, schoolID: scope.schoolID), result.version > command.resourceVersion,
                  command.resourceID.map({ $0 == result.id }) ?? true,
                  result.status == (command.kind == .revokeInvitation ? .revoked : .pending) else {
                throw SchoolInvitationFailure.invalidResponse
            }
            try outbox.remove(command)
            guard request == generation else { return true }
            pending = nil; pendingRequiresReview = false; isBusy = false
            if command.kind == .createInvitation { email = ""; selectedRoles = [.learner] }
            if let index = invitations.firstIndex(where: { $0.id == result.id }) { invitations[index] = result }
            else { invitations.insert(result, at: 0) }
            successMessage = command.kind == .revokeInvitation ? "Invitation révoquée. Le lien ne permet plus de rejoindre l’école."
                : "Invitation enregistrée. La réception de l’e-mail n’est pas confirmée ici."
            await load()
            return true
        } catch {
            if let failure = error as? SchoolInvitationFailure, failure.permitsCorrectionOfFreshRequest {
                if firstAttempt {
                    do { try outbox.remove(command) }
                    catch {
                        guard request == generation else { return false }
                        isBusy = false; storageAccessible = false; fail(error); return false
                    }
                    guard request == generation else { return false }
                    pending = nil; needsReload = true
                } else {
                    guard request == generation else { return false }
                    pendingRequiresReview = true
                }
            }
            guard request == generation else { return false }
            if error as? SchoolInvitationFailure == .pendingCommand { pendingRequiresReview = true }
            isBusy = false; fail(error)
            return false
        }
    }

    private func validate(_ page: SchoolPage<SchoolInvitation>) throws {
        guard page.items.count <= 100, Set(page.items.map(\.id)).count == page.items.count,
              page.items.allSatisfy({ SchoolInvitationClient.valid($0, schoolID: scope.schoolID)
                  && Set($0.roles).isSubset(of: Set(allowedRoles)) }) else { throw SchoolInvitationFailure.invalidResponse }
    }

    private func valid(email: String, roles: Set<SchoolInvitationRole>) -> Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty } && value.unicodeScalars.count <= 254
            && !value.contains(where: \.isWhitespace) && !roles.isEmpty && roles.isSubset(of: Set(allowedRoles))
    }

    static func reasonIsValid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.unicodeScalars.count <= 1000
    }

    private func fail(_ error: any Error) {
        if let failure = error as? SchoolInvitationFailure {
            errorMessage = failure.localizedDescription
            if failure == .unauthorized || failure == .forbidden {
                school = nil; invitations = []; nextCursor = nil; selectedID = nil
                email = ""; selectedRoles = [.learner]; successMessage = nil
                storageAccessible = false; hasLoaded = false
                generation = UUID(); pageRequest = UUID(); isLoading = false; isLoadingMore = false
                accessFailure = failure
            }
        } else if let failure = error as? SchoolConfigurationFailure { errorMessage = failure.localizedDescription }
        else { errorMessage = SchoolInvitationFailure.unavailable.localizedDescription }
    }
}
