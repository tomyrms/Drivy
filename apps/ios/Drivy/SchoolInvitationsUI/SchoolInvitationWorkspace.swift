import Foundation
import Observation

/// A code just handed back by the school. Kept in memory only, for this screen.
struct SchoolIssuedInvitationCode: Identifiable, Equatable {
    let invitationID: UUID
    /// Display form, `XXXX-XXXX`.
    let code: String
    let expiresAt: String
    var id: String { "\(invitationID.uuidString):\(code)" }
}

/// A code invitation whose creation is confirmed but whose code was not returned
/// (a replayed answer or a receipt never carries it): a new code can be issued for it.
struct SchoolCodeRecovery: Equatable {
    let invitationID: UUID
    let version: Int
}

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
    private(set) var hasLoaded = false
    private(set) var isLoadingMore = false
    private(set) var isBusy = false
    private(set) var needsReload = false
    private(set) var pendingRequiresReview = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var accessFailure: SchoolInvitationFailure?
    private(set) var offerings: [SchoolOffering] = []
    private(set) var instructors: [SchoolInvitationInstructor] = []
    private(set) var creationOptionsError: String?
    private(set) var issuedCode: SchoolIssuedInvitationCode?
    private(set) var codeRecovery: SchoolCodeRecovery?
    var email = ""
    var selectedRoles: Set<SchoolInvitationRole> = [.learner]
    var selectedOfferingID: UUID?
    var selectedOfferingIDs: Set<UUID> = []
    var selectedInstructorID: UUID?
    var selectedID: UUID?

    @ObservationIgnored private let api: any SchoolInvitationAPI
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var pageRequest = UUID()
    @ObservationIgnored private var seenCursors: Set<String> = []
    @ObservationIgnored private var storageAccessible = false
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
    /// Un moniteur invite l'élève dans sa formation et s'y affecte lui-même.
    var carriesTraining: Bool { canCreateCode && selectedRoles == [.learner] }
    var selectedOffering: SchoolOffering? { offerings.first { $0.id == selectedOfferingID } }
    var selectedInvitation: SchoolInvitation? { invitations.first { $0.id == selectedID } }
    var canCreateCode: Bool { allowedRoles.contains(.learner) }
    var selectedOfferings: [SchoolOffering] { offerings.filter { selectedOfferingIDs.contains($0.id) } }
    var codeDraftIsValid: Bool {
        canCreateCode && carriesTraining && creationOptionsError == nil && !selectedOfferingIDs.isEmpty
            && selectedOfferingIDs.count <= 16 && selectedOfferings.count == selectedOfferingIDs.count
            && (roles.contains("ADMIN") ? instructors.contains { $0.id == selectedInstructorID }
                : selectedInstructorID == scope.membershipID)
    }
    /// Loaded, but no training is open for a code yet.
    var lacksOpenTraining: Bool { hasLoaded && canCreateCode && creationOptionsError == nil && offerings.isEmpty }
    var lacksInstructor: Bool { hasLoaded && roles.contains("ADMIN") && creationOptionsError == nil && instructors.isEmpty }
    /// « Permis B » for a code invitation, when the training is known.
    func trainingLabel(_ invitation: SchoolInvitation) -> String? {
        let trainingIDs = Set((invitation.trainings ?? invitation.training.map { [$0] } ?? []).map(\.offeringId))
        let categories = Set(offerings.filter { trainingIDs.contains($0.id) }.map(\.categoryCode)).sorted()
        if !categories.isEmpty { return "Permis \(categories.joined(separator: ", "))" }
        return invitation.trainingCategoryCode.map { "Permis \($0)" }
    }

    func dismissIssuedCode() { issuedCode = nil }

    func invalidate() {
        generation = UUID(); pageRequest = UUID(); isInvalidated = true
        issuedCode = nil; codeRecovery = nil
        school = nil; invitations = []; nextCursor = nil; selectedID = nil; pending = nil; offerings = []; instructors = []
        selectedOfferingIDs = []; selectedInstructorID = nil; creationOptionsError = nil
        email = ""; selectedRoles = [.learner]; selectedOfferingID = nil; errorMessage = nil; successMessage = nil
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
            invitations = page.items.map(\.withoutCode); nextCursor = page.nextCursor; seenCursors = []
            if !invitations.contains(where: { $0.id == selectedID }) { selectedID = nil }
            if canCreateCode {
                creationOptionsError = nil
                do {
                    let offerings = try await api.trainingOfferings(schoolID: scope.schoolID)
                    guard request == generation else { return }
                    let instructors: [SchoolInvitationInstructor]
                    if roles.contains("ADMIN") {
                        instructors = try await api.instructors(schoolID: scope.schoolID)
                        guard request == generation else { return }
                    } else { instructors = [] }
                    // Publish a complete context: a failed instructor read must not erase a selected permit.
                    self.offerings = offerings
                    self.instructors = instructors
                    if !offerings.contains(where: { $0.id == selectedOfferingID }) { selectedOfferingID = offerings.count == 1 ? offerings[0].id : nil }
                    selectedOfferingIDs.formIntersection(Set(offerings.map(\.id)))
                    if selectedOfferingIDs.isEmpty, offerings.count == 1 { selectedOfferingIDs = [offerings[0].id] }
                    if roles.contains("ADMIN") {
                        if !instructors.contains(where: { $0.id == selectedInstructorID }) {
                            selectedInstructorID = instructors.first { $0.id == scope.membershipID }?.id
                                ?? (instructors.count == 1 ? instructors[0].id : nil)
                        }
                    } else { selectedInstructorID = scope.membershipID }
                } catch {
                    guard request == generation else { return }
                    if error as? SchoolInvitationFailure == .unauthorized || error as? SchoolInvitationFailure == .forbidden { throw error }
                    creationOptionsError = "Les permis et moniteurs n’ont pas pu être chargés. Réessaie."
                }
            }
            hasLoaded = true; needsReload = false; isLoading = false
            errorMessage = storageError ?? (receiptRefused
                ? "Tes droits ne permettent pas de vérifier cette demande. Sa référence reste conservée." : nil)
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
            for item in page.items.map(\.withoutCode) {
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
    func inviteAfterConfirmation(email: String, roles: Set<SchoolInvitationRole>, offeringID: UUID? = nil) async -> Bool {
        guard mayEdit, valid(email: email, roles: roles) else { return false }
        let id = UUID()
        let training = roles == [.learner] && self.roles.contains("INSTRUCTOR") && offerings.contains(where: { $0.id == offeringID })
            ? offeringID.map { SchoolInvitationTraining(offeringId: $0, instructorMembershipId: scope.membershipID) } : nil
        let command = SchoolInviteCommand(operationId: id, email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            roles: SchoolInvitationRole.allCases.filter { roles.contains($0) }, training: training)
        let confirmed = await prepare(command, id: id, kind: .createInvitation, resource: nil, version: 0)
        if confirmed && !isInvalidated { self.email = ""; selectedRoles = [.learner] }
        return confirmed
    }

    /// Single-use code for a learner, carrying every selected training and its instructor.
    /// Same outbox as every invitation command: stored encrypted before it is sent.
    @discardableResult
    func createCode() async -> Bool {
        guard mayEdit, codeDraftIsValid, let instructorID = selectedInstructorID else { return false }
        let id = UUID()
        let trainings = selectedOfferings.map { SchoolInvitationTraining(offeringId: $0.id, instructorMembershipId: instructorID) }
        issuedCode = nil; codeRecovery = nil
        let command = SchoolInviteCommand(operationId: id, delivery: .code, roles: [.learner], trainings: trainings)
        return await prepare(command, id: id, kind: .createInvitation, resource: nil, version: 0)
    }

    /// New code for a code invitation whose code was not returned; the old one stops working.
    @discardableResult
    func renewRecoveredCode() async -> Bool {
        guard mayEdit, let recovery = codeRecovery else { return false }
        if let listed = invitations.first(where: { $0.id == recovery.invitationID }), listed.version >= recovery.version {
            return await resendAfterConfirmation(listed)
        }
        let id = UUID()
        return await prepare(SchoolResendInvitationCommand(operationId: id), id: id, kind: .resendInvitation,
            resource: recovery.invitationID, version: recovery.version)
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
            if issuesCode(command) {
                // A receipt never carries the code: only a new one can be handed over.
                successMessage = nil
                codeRecovery = SchoolCodeRecovery(invitationID: receipt.resourceId, version: receipt.resourceVersion)
            } else {
                successMessage = "Le résultat de la demande a été confirmé."
            }
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
            let listed = result.withoutCode
            if let index = invitations.firstIndex(where: { $0.id == result.id }) { invitations[index] = listed }
            else { invitations.insert(listed, at: 0) }
            if result.isCode {
                successMessage = command.kind == .revokeInvitation ? "Code révoqué." : nil
                receiveCode(result, command: command)
            } else {
                successMessage = command.kind == .revokeInvitation ? "Invitation révoquée. Le lien ne permet plus de rejoindre l’école."
                    : "Invitation enregistrée. La réception de l’e-mail n’est pas confirmée ici."
            }
            await load()
            return true
        } catch {
            if let failure = error as? SchoolInvitationFailure, failure.permitsCorrectionOfFreshRequest {
                // A resent command is kept for review, unless the refusal proves it never took effect
                // (an e-mail invitation without delivery must not block the school's other requests).
                if firstAttempt || failure.provesNotCommitted {
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

    private func issuesCode(_ command: PendingSchoolCommand) -> Bool {
        switch command.kind {
        case .createInvitation:
            return (try? JSONDecoder().decode(SchoolInviteCommand.self, from: command.body))?.delivery == .code
        case .resendInvitation:
            return invitations.first(where: { $0.id == command.resourceID })?.isCode == true
                || codeRecovery?.invitationID == command.resourceID
        default:
            return false
        }
    }

    /// A created or renewed code is shown once. A replayed answer carries no code: the
    /// invitation exists, and only a new code can be handed over.
    private func receiveCode(_ result: SchoolInvitation, command: PendingSchoolCommand) {
        guard command.kind != .revokeInvitation else {
            if codeRecovery?.invitationID == result.id { codeRecovery = nil }
            if issuedCode?.invitationID == result.id { issuedCode = nil }
            return
        }
        if let raw = result.code, let code = SchoolInvitationCode.display(raw) {
            issuedCode = SchoolIssuedInvitationCode(invitationID: result.id, code: code, expiresAt: result.expiresAt)
            codeRecovery = nil
        } else {
            issuedCode = nil
            codeRecovery = SchoolCodeRecovery(invitationID: result.id, version: result.version)
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
                offerings = []; instructors = []; selectedOfferingIDs = []; selectedOfferingID = nil; selectedInstructorID = nil
                creationOptionsError = nil
                email = ""; selectedRoles = [.learner]; successMessage = nil; issuedCode = nil; codeRecovery = nil
                storageAccessible = false; hasLoaded = false
                generation = UUID(); pageRequest = UUID(); isLoading = false; isLoadingMore = false
                accessFailure = failure
            }
        } else if let failure = error as? SchoolConfigurationFailure { errorMessage = failure.localizedDescription }
        else { errorMessage = SchoolInvitationFailure.unavailable.localizedDescription }
    }
}
