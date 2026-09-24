import Foundation
import Observation

@MainActor @Observable final class SchoolMemberWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let client: SchoolMemberClient
    private(set) var school: SchoolDetails?
    private(set) var members: [SchoolMember] = []
    private(set) var pending: PendingSchoolCommand?
    private(set) var selectedMember: SchoolMember?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var needsReload = true
    private(set) var accessRevoked = false
    private(set) var ownAccessChanged = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var pendingRequiresReview = false
    private(set) var locatedLearner: SchoolLearner?
    private(set) var needsReauthentication = false
    var search = ""
    var roles = Set<String>()
    var grants = Set<String>()
    var reason = ""
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lookupGeneration = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var storageAvailable = false

    init(scope: SchoolCommandScope, client: SchoolMemberClient, outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.client = client; self.outbox = outbox
    }
    var filteredMembers: [SchoolMember] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return members }
        return members.filter { $0.displayName.localizedStandardContains(query) }
    }
    var availableForLearnerRole: [SchoolMember] { filteredMembers.filter { $0.status == "ACTIVE" && !$0.roles.contains("LEARNER") } }
    var canMutate: Bool { !invalidated && !accessRevoked && !ownAccessChanged && !isBusy && !isLoading && !needsReload && storageAvailable && pending == nil && school?.status == "ACTIVE" }
    var isChanged: Bool { guard let selectedMember else { return false }; return roles != Set(selectedMember.roles) || grants != Set(selectedMember.grants) }
    var removesOwnAdmin: Bool { selectedMember?.id == scope.membershipID && !roles.contains("ADMIN") }
    var isLastAdministrator: Bool { selectedMember?.roles.contains("ADMIN") == true && members.filter { $0.status == "ACTIVE" && $0.roles.contains("ADMIN") }.count == 1 }
    var canSave: Bool {
        canMutate && selectedMember?.status == "ACTIVE" && isChanged && !roles.isEmpty
        && roles.isSubset(of: Set(SchoolMemberRole.allCases.map(\.rawValue)))
        && grants.isSubset(of: Set(SchoolMemberGrant.allCases.map(\.rawValue)))
        && (!isLastAdministrator || roles.contains("ADMIN"))
        && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.unicodeScalars.count <= 1000
    }
    var canRetry: Bool { !invalidated && !accessRevoked && !isBusy && !isLoading && pending?.kind == .updateMember && pending?.scope == scope && !pendingRequiresReview }
    var hasUnsavedChanges: Bool { isChanged || !reason.isEmpty }

    func invalidate() { invalidated = true; generation = UUID(); lookupGeneration = UUID(); clear() }
    private func clear() {
        school = nil; members = []; selectedMember = nil; roles = []; grants = []; reason = ""; locatedLearner = nil
        pending = nil; storageAvailable = false; needsReload = true; isBusy = false; isLoading = false
    }
    func load() async {
        guard !invalidated, !isBusy, !ownAccessChanged else { return }
        generation = UUID(); let request = generation
        isLoading = true; needsReload = true; errorMessage = nil; storageAvailable = false
        var storageError: String?
        do { pending = try outbox.pending(for: scope); storageAvailable = true }
        catch { storageError = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            let person = try await client.reader.me()
            guard person.personId == scope.personID,
                  let actor = person.memberships.first(where: { $0.membershipId == scope.membershipID }),
                  actor.schoolId == scope.schoolID, actor.accessEpoch == scope.accessEpoch, actor.roles.contains("ADMIN") else { throw SchoolCatalogFailure.forbidden }
            let school = try await client.reader.school(id: scope.schoolID)
            let members = try await client.members(schoolID: scope.schoolID)
            guard request == generation, !Task.isCancelled else { return }
            self.school = school; self.members = members; needsReload = false; isLoading = false; errorMessage = storageError
            if let selectedMember {
                if let updated = members.first(where: { $0.id == selectedMember.id }) { selectCurrentVersion(updated.id) }
                else { clearSelection() }
            }
        } catch { guard request == generation else { return }; isLoading = false; fail(error) }
    }
    func select(_ member: SchoolMember, addLearner: Bool = false) {
        guard !isBusy, !invalidated, members.contains(where: { $0.id == member.id }) else { return }
        selectedMember = member; roles = Set(member.roles); grants = Set(member.grants); reason = ""
        errorMessage = nil; successMessage = nil; locatedLearner = nil; lookupGeneration = UUID()
        if addLearner { roles.insert("LEARNER") }
    }
    func clearSelection() {
        selectedMember = nil; roles = []; grants = []; reason = ""; locatedLearner = nil; lookupGeneration = UUID()
    }
    func saveAfterReauthentication() async -> Bool {
        guard canSave, let selectedMember else { return false }
        let id = UUID()
        do {
            let body = SchoolUpdateMemberCommand(operationId: id, roles: roles.sorted(), grants: grants.sorted(), reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let command = PendingSchoolCommand(id: id, scope: scope, kind: .updateMember, resourceVersion: selectedMember.version,
                createdAt: Date(), body: try encoder.encode(body), resourceID: selectedMember.id)
            pending = command; pendingRequiresReview = false
            do { try outbox.save(command) }
            catch { storageAvailable = false; if let value = try? outbox.pending(for: scope) { pending = value }; throw error }
        } catch { fail(error); return false }
        return await transmit(firstAttempt: true)
    }
    func retryAfterReauthentication() async -> Bool { await transmit(firstAttempt: false) }
    func verify() async {
        guard !invalidated, !accessRevoked, !isBusy, let command = pending, command.scope.belongsToWorkspace(scope) else { return }
        isBusy = true; let request = generation
        do {
            _ = try await client.receipt(command); try outbox.remove(command)
            guard request == generation else { return }
            pending = nil; isBusy = false; pendingRequiresReview = false
            successMessage = "La modification a été enregistrée par l’école."
            if command.kind == .updateMember, command.resourceID == scope.membershipID { ownAccessChanged = true; return }
            await load()
            if let selectedMember { selectCurrentVersion(selectedMember.id) }
        } catch { guard request == generation else { return }; isBusy = false; fail(error) }
    }
    func findLearner(for member: SchoolMember) async {
        guard !invalidated, !isBusy, member.roles.contains("LEARNER") else { return }
        lookupGeneration = UUID(); let lookup = lookupGeneration; let request = generation
        isBusy = true; errorMessage = nil
        do {
            let value = try await client.learner(schoolID: scope.schoolID, personID: member.personId)
            guard request == generation, lookup == lookupGeneration else { return }
            locatedLearner = value; isBusy = false
            if value == nil { errorMessage = "Le dossier n’est pas encore accessible. Actualisez les informations de l’école." }
        } catch { guard request == generation, lookup == lookupGeneration else { return }; isBusy = false; fail(error) }
    }
    private func transmit(firstAttempt: Bool) async -> Bool {
        guard canRetry, let command = pending else { return false }
        let request = generation; isBusy = true; errorMessage = nil; successMessage = nil; needsReauthentication = false
        do {
            try outbox.save(command)
            let updated = try await client.send(command)
            try outbox.remove(command)
            guard request == generation else { return true }
            pending = nil; isBusy = false; roles = Set(updated.roles); grants = Set(updated.grants); reason = ""
            selectedMember = updated; successMessage = "Les accès ont été enregistrés."
            if updated.id == scope.membershipID { ownAccessChanged = true; return true }
            await load(); return true
        } catch {
            guard request == generation else { return false }
            if let failure = error as? SchoolCatalogFailure, failure.permitsFreshCorrection {
                if firstAttempt {
                    do { try outbox.remove(command); pending = nil; needsReload = true }
                    catch { storageAvailable = false; isBusy = false; fail(error); return false }
                } else { pendingRequiresReview = true }
            }
            isBusy = false; fail(error); return false
        }
    }
    private func selectCurrentVersion(_ id: UUID) {
        guard let value = members.first(where: { $0.id == id }) else { clearSelection(); return }
        selectedMember = value; roles = Set(value.roles); grants = Set(value.grants); reason = ""
    }
    private func fail(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Les accès n’ont pas pu être mis à jour."
        if error as? SchoolCatalogFailure == .reauthentication { needsReauthentication = true }
        if error as? SchoolCatalogFailure == .forbidden || error as? SchoolCatalogFailure == .unauthorized
            || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .unauthorized {
            clear(); accessRevoked = true
        }
    }
}
