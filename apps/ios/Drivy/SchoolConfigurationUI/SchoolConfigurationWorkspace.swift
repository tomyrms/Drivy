import Foundation
import Observation

@MainActor
@Observable
final class SchoolConfigurationWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    private(set) var school: SchoolDetails?
    private(set) var setup: SchoolSetup?
    private(set) var readiness: SchoolReadiness?
    private(set) var policy: SchoolDataPolicy?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var needsReload = false
    private(set) var pendingRequiresReview = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var accessFailure: SchoolConfigurationFailure?
    var name = ""
    var contactEmail = ""
    var contactPhone = ""
    var noticeText = ""
    var retentionText = ""
    var policyContactEmail = ""

    @ObservationIgnored private let api: any SchoolConfigurationAPI
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var isInvalidated = false
    @ObservationIgnored private var storageAccessible = false

    init(scope: SchoolCommandScope, api: any SchoolConfigurationAPI,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope
        self.api = api
        self.outbox = outbox
    }

    var mayEdit: Bool { hasLoaded && storageAccessible && !isInvalidated && !isLoading && !isBusy && pending == nil && !needsReload }
    var canRetryPending: Bool { pending?.scope == scope && pending?.kind.isInvitation == false && !pendingRequiresReview && !isBusy && !isLoading && !isInvalidated }
    var identityIsValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.unicodeScalars.count <= 150
            && Self.emailIsValid(contactEmail) && contactPhone.unicodeScalars.count <= 32
    }
    var policyIsValid: Bool {
        [noticeText, retentionText].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.unicodeScalars.count <= 20_000
        } && Self.emailIsValid(policyContactEmail)
    }
    var identityIsEdited: Bool {
        guard let school else { return false }
        return name != school.name || contactEmail != school.contactEmail || contactPhone != (school.contactPhone ?? "")
    }
    var policyIsEdited: Bool {
        guard let policy else { return false }
        return noticeText != policy.noticeText || retentionText != policy.retentionText
            || policyContactEmail != (policy.contactEmail ?? school?.contactEmail ?? "")
    }
    var canActivate: Bool {
        mayEdit && school?.status == "DRAFT" && readiness?.activationReady == true
            && policy?.status == "APPROVED" && !identityIsEdited && !policyIsEdited
    }

    func invalidate() {
        generation = UUID()
        isInvalidated = true
        school = nil; setup = nil; readiness = nil; policy = nil; pending = nil
        name = ""; contactEmail = ""; contactPhone = ""
        noticeText = ""; retentionText = ""; policyContactEmail = ""
        isLoading = false; isBusy = false
    }

    func load() async {
        guard !isInvalidated, !isBusy else { return }
        generation = UUID()
        let request = generation
        isLoading = true
        errorMessage = nil
        storageAccessible = false
        do {
            pending = try outbox.pending(for: scope)
            if pending == nil { pendingRequiresReview = false }
            storageAccessible = true
            let school = try await api.school(id: scope.schoolID)
            guard request == generation else { return }
            let setup = try await api.setup(schoolID: scope.schoolID)
            guard request == generation else { return }
            let policy = try await api.dataPolicy(schoolID: scope.schoolID)
            guard request == generation else { return }
            let readiness = try await api.readiness(schoolID: scope.schoolID)
            guard request == generation else { return }
            guard school.id == scope.schoolID, setup.schoolId == scope.schoolID,
                  policy.schoolId == scope.schoolID, readiness.schoolId == scope.schoolID else {
                throw SchoolConfigurationFailure.invalidResponse
            }
            self.school = school; self.setup = setup; self.policy = policy; self.readiness = readiness
            if !hasLoaded { populateIdentity(school); populatePolicy(policy) }
            hasLoaded = true
            needsReload = false
            isLoading = false
        } catch {
            guard request == generation else { return }
            isLoading = false
            fail(error)
        }
    }

    func saveIdentityAfterConfirmation() async {
        guard mayEdit, identityIsValid, let school else { return }
        let operation = UUID()
        let value = SchoolIdentityCommand(operationId: operation, name: name, timeZone: school.timeZone,
            contactEmail: contactEmail, contactPhone: contactPhone.isEmpty ? nil : contactPhone, impactConfirmed: true)
        await prepare(value, operation: operation, kind: .updateSchool, version: school.version)
    }

    func adoptPolicyAfterReview() async {
        guard mayEdit, policyIsValid, let policy else { return }
        let operation = UUID()
        let value = SchoolDataPolicyCommand(operationId: operation, noticeText: noticeText,
            retentionText: retentionText, contactEmail: policyContactEmail,
            reviewAcknowledged: true)
        await prepare(value, operation: operation, kind: .saveDataPolicy, version: policy.version)
    }

    func saveProgress() async {
        guard mayEdit, !identityIsEdited, !policyIsEdited, let setup else { return }
        let operation = UUID()
        var completed = setup.completedSteps
        if identityIsValid && !completed.contains("IDENTITY") { completed.append("IDENTITY") }
        if policy?.status == "APPROVED" && !completed.contains("DATA") { completed.append("DATA") }
        let value = SchoolSetupCommand(operationId: operation, currentStep: "REVIEW", completedSteps: completed)
        await prepare(value, operation: operation, kind: .saveSetup, version: setup.version)
    }

    func activateAfterReview() async {
        guard canActivate, let school, let readiness else { return }
        let operation = UUID()
        let value = SchoolActivationCommand(operationId: operation,
            expectedConfigurationVersion: readiness.configurationVersion, reviewAcknowledged: true)
        await prepare(value, operation: operation, kind: .activate, version: school.version)
    }

    func verifyPending() async {
        guard !isBusy, !isLoading, !isInvalidated, let command = pending else { return }
        let request = generation
        isBusy = true
        do {
            let receipt = try await api.operation(schoolID: scope.schoolID, id: command.id)
            guard command.matches(receipt) else { throw SchoolConfigurationFailure.invalidResponse }
            try outbox.remove(command)
            guard request == generation else { return }
            pending = nil
            pendingRequiresReview = false
            isBusy = false
            successMessage = "Le résultat de la demande a été confirmé."
            await load()
            if command.kind == .saveDataPolicy, let policy { populatePolicy(policy) }
            if [.updateSchool, .activate].contains(command.kind), let school { populateIdentity(school) }
        } catch {
            guard request == generation else { return }
            isBusy = false
            fail(error)
        }
    }

    func retryPending() async { await transmit(isFirstAttempt: false) }

    private func prepare<Value: Encodable>(_ value: Value, operation: UUID, kind: SchoolCommandKind, version: Int) async {
        guard mayEdit else { return }
        successMessage = nil
        errorMessage = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let command = PendingSchoolCommand(id: operation, scope: scope, kind: kind,
                resourceVersion: version, createdAt: Date(), body: try encoder.encode(value))
            try outbox.save(command)
            pending = command
            pendingRequiresReview = false
        } catch {
            storageAccessible = false
            fail(error)
            return
        }
        await transmit(isFirstAttempt: true)
    }

    private func transmit(isFirstAttempt: Bool) async {
        guard canRetryPending, let command = pending else { return }
        let request = generation
        do { try outbox.save(command) }
        catch {
            storageAccessible = false
            fail(error)
            return
        }
        isBusy = true
        errorMessage = nil
        do {
            let result = try await api.send(command)
            // Clear a durably acknowledged command even if its screen closed.
            try outbox.remove(command)
            guard request == generation else { return }
            pending = nil
            pendingRequiresReview = false
            isBusy = false
            switch result {
            case .school(let value): school = value; populateIdentity(value)
            case .setup(let value): setup = value
            case .dataPolicy(let value): policy = value; populatePolicy(value)
            }
            successMessage = command.kind == .activate ? "Votre école est activée." : "Modification confirmée par l’école."
            await load()
        } catch {
            if error as? SchoolConfigurationFailure == .pendingCommand {
                guard request == generation else { return }
                pendingRequiresReview = true
            }
            if let failure = error as? SchoolConfigurationFailure, failure.permitsCorrectionOfFreshRequest {
                if isFirstAttempt {
                    do { try outbox.remove(command) }
                    catch {
                        guard request == generation else { return }
                        isBusy = false
                        fail(SchoolConfigurationFailure.storage)
                        return
                    }
                    guard request == generation else { return }
                    pending = nil
                    needsReload = true
                } else {
                    guard request == generation else { return }
                    pendingRequiresReview = true
                }
            }
            // No rejection of a retry disproves the first attempt's effect.
            guard request == generation else { return }
            isBusy = false
            fail(error)
        }
    }

    private func populateIdentity(_ value: SchoolDetails) {
        name = value.name; contactEmail = value.contactEmail; contactPhone = value.contactPhone ?? ""
    }

    private func populatePolicy(_ value: SchoolDataPolicy) {
        noticeText = value.noticeText; retentionText = value.retentionText
        policyContactEmail = value.contactEmail ?? school?.contactEmail ?? ""
    }

    private func fail(_ error: any Error) {
        let failure = error as? SchoolConfigurationFailure ?? .unavailable
        errorMessage = failure.localizedDescription
        if failure == .unauthorized || failure == .forbidden { accessFailure = failure }
    }

    private static func emailIsValid(_ value: String) -> Bool {
        let pieces = value.split(separator: "@", omittingEmptySubsequences: false)
        return pieces.count == 2 && pieces.allSatisfy { !$0.isEmpty }
            && value.unicodeScalars.count <= 254 && !value.contains(where: \.isWhitespace)
    }

}
