import Foundation
import Observation

@MainActor @Observable
final class SchoolProfileWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let roles: [String]
    let learnerID: UUID?
    let isOwnProfile: Bool
    let onboardingKind: SchoolOnboardingKind?
    private(set) var school: SchoolDetails?
    private(set) var policies: [SchoolProfilePolicy] = []
    private(set) var nextCursor: String?
    private(set) var notice: SchoolDataPolicy?
    private(set) var publicationNotice: SchoolDataPolicy?
    private(set) var reviewingPolicyID: UUID?
    private(set) var isLoadingPublication = false
    private(set) var profile: SchoolAdministrativeProfile?
    private(set) var readiness: SchoolLearnerReadiness?
    private(set) var onboarding: SchoolOnboarding?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var needsReload = true
    private(set) var pendingRequiresReview = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var accessFailure: SchoolProfileFailure?
    var draft = SchoolProfileDraft()
    @ObservationIgnored private let api: any SchoolProfileAPI
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var storageAccessible = false
    @ObservationIgnored private var seenCursors: Set<String> = []
    @ObservationIgnored private var reviewGeneration = UUID()

    init(scope: SchoolCommandScope, roles: [String], learnerID: UUID? = nil, isOwnProfile: Bool = false,
         onboardingKind: SchoolOnboardingKind? = nil, api: any SchoolProfileAPI,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.roles = roles; self.learnerID = learnerID; self.isOwnProfile = isOwnProfile
        self.onboardingKind = onboardingKind; self.api = api; self.outbox = outbox
    }
    var isPolicyManagement: Bool { learnerID == nil && onboardingKind == nil }
    var applicablePolicy: SchoolProfilePolicy? {
        if let reference = profile?.policyVersionId ?? onboarding?.policyVersionId {
            return policies.first { $0.id == reference && $0.status == "PUBLISHED" }
        }
        return policies.filter { $0.status == "PUBLISHED" && (SchoolInvitation.date($0.effectiveFrom) ?? .distantFuture) <= Date() }
            .max { ($0.effectiveFrom, $0.version) < ($1.effectiveFrom, $1.version) }
    }
    var canMutate: Bool {
        !invalidated && !isLoading && !isBusy && !needsReload && storageAccessible && pending == nil && school?.status != "ARCHIVED" && school != nil
    }
    var editableFields: Set<SchoolProfileField> {
        guard let policy = applicablePolicy else { return [] }
        var fields = Set(policy.fields.map(\.field)); fields.remove(.profilePhotoDocumentId)
        if !isOwnProfile && !roles.contains("ADMIN") { fields.formIntersection([.contactEmail, .contactPhone]) }
        return fields
    }
    var hasEdits: Bool { profile.map { !draft.changes(from: $0, allowed: editableFields).isEmpty } ?? false }
    var canSaveProfile: Bool {
        canMutate && hasEdits && draft.isValid(allowed: editableFields, timeZone: school?.timeZone ?? "Europe/Zurich")
    }
    var canCreatePolicy: Bool { canMutate && roles.contains("ADMIN") && notice?.status == "APPROVED" && notice?.noticeVersionId != nil }
    var canRetryPending: Bool {
        guard let pending else { return false }
        return pending.kind.isProfile && pending.scope == scope && !pendingRequiresReview && !invalidated && !isBusy && !isLoading
            && ownsRoute(pending)
    }
    var canVerifyPending: Bool { pending != nil && !invalidated && !isBusy && !isLoading }

    func invalidate() {
        generation = UUID(); invalidated = true; school = nil; policies = []; notice = nil; profile = nil
        onboarding = nil; readiness = nil; pending = nil; nextCursor = nil; draft = SchoolProfileDraft()
        errorMessage = nil; successMessage = nil; isLoading = false; isBusy = false; storageAccessible = false
        reviewGeneration = UUID(); publicationNotice = nil; reviewingPolicyID = nil; isLoadingPublication = false
    }
    func load(preserveDraft: Bool = true, receiptRefused: Bool = false) async {
        guard !invalidated, !isBusy else { return }
        generation = UUID(); let request = generation
        reviewGeneration = UUID(); publicationNotice = nil; reviewingPolicyID = nil; isLoadingPublication = false
        let changedKeys: Set<String> = preserveDraft ? Set(profile.map { draft.changes(from: $0, allowed: editableFields).keys.map { $0 } } ?? []) : []
        let previousDraft = draft
        isLoading = true; needsReload = true; errorMessage = nil; storageAccessible = false
        var storageError: String?
        do { pending = try outbox.pending(for: scope); storageAccessible = true }
        catch { storageError = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            let school = try await api.school(id: scope.schoolID)
            guard request == generation else { return }
            guard school.id == scope.schoolID else { throw SchoolProfileFailure.invalidResponse }
            self.school = school
            let page = try await api.policies(schoolID: scope.schoolID, cursor: nil)
            guard request == generation else { return }
            try validate(page); policies = page.items; nextCursor = page.nextCursor; seenCursors = []
            if isPolicyManagement {
                guard roles.contains("ADMIN") else { throw SchoolProfileFailure.forbidden }
                let notice = try await api.notice(schoolID: scope.schoolID, id: nil)
                guard request == generation else { return }; self.notice = notice
            } else {
                if let learnerID {
                    let profile = try await api.profile(schoolID: scope.schoolID, learnerID: learnerID)
                    guard request == generation else { return }
                    guard SchoolProfileClient.valid(profile, schoolID: scope.schoolID, learnerID: learnerID) else { throw SchoolProfileFailure.invalidResponse }
                    self.profile = profile
                    draft = previousDraft.rebased(on: profile, changedKeys: changedKeys)
                    let readiness = try await api.readiness(schoolID: scope.schoolID, learnerID: learnerID, action: "ENTER")
                    guard request == generation else { return }
                    guard readiness.learnerId == learnerID, readiness.action == "ENTER" else { throw SchoolProfileFailure.invalidResponse }
                    self.readiness = readiness
                }
                if let onboardingKind {
                    let value = try await api.onboarding(schoolID: scope.schoolID, kind: onboardingKind)
                    guard request == generation else { return }
                    guard value.personId == scope.personID, value.membershipId == scope.membershipID else { throw SchoolProfileFailure.invalidResponse }
                    onboarding = value
                }
                if let reference = profile?.policyVersionId ?? onboarding?.policyVersionId {
                    while !policies.contains(where: { $0.id == reference }), let cursor = nextCursor {
                        guard seenCursors.count < 100, !seenCursors.contains(cursor) else { throw SchoolProfileFailure.invalidResponse }
                        seenCursors.insert(cursor)
                        let page = try await api.policies(schoolID: scope.schoolID, cursor: cursor)
                        guard request == generation else { return }; try validate(page)
                        policies.append(contentsOf: page.items.filter { incoming in !policies.contains(where: { $0.id == incoming.id }) })
                        nextCursor = page.nextCursor
                    }
                    guard applicablePolicy != nil else { throw SchoolProfileFailure.invalidResponse }
                }
                if let policy = applicablePolicy {
                    let notice = try await api.notice(schoolID: scope.schoolID, id: policy.noticeVersionId)
                    guard request == generation else { return }; self.notice = notice
                }
            }
            isLoading = false; needsReload = false
            errorMessage = storageError ?? (receiptRefused ? "Le résultat ne peut pas être consulté avec vos droits actuels. Sa référence reste conservée." : nil)
        } catch {
            guard request == generation else { return }; isLoading = false; fail(error)
        }
    }
    func loadMorePolicies() async {
        guard !invalidated, !isLoading, !isBusy, let cursor = nextCursor else { return }
        let request = generation; isLoading = true
        do {
            let page = try await api.policies(schoolID: scope.schoolID, cursor: cursor)
            guard request == generation else { return }; try validate(page)
            guard page.nextCursor != cursor, page.nextCursor.map({ !seenCursors.contains($0) }) ?? true else { throw SchoolProfileFailure.invalidResponse }
            seenCursors.insert(cursor)
            for item in page.items {
                if let index = policies.firstIndex(where: { $0.id == item.id }) { if policies[index].version <= item.version { policies[index] = item } }
                else { policies.append(item) }
            }
            nextCursor = page.nextCursor; isLoading = false
        } catch { guard request == generation else { return }; isLoading = false; fail(error) }
    }
    @discardableResult
    func createPolicyAfterConfirmation(_ draft: SchoolProfilePolicyDraft) async -> Bool {
        guard canCreatePolicy, draft.isValid, let school, let noticeID = notice?.noticeVersionId else { return false }
        let id = UUID()
        let payload = SchoolProfilePolicyCommand(operationId: id, effectiveFrom: ISO8601DateFormatter().string(from: draft.effectiveFrom),
            fields: draft.selectedRules, noticeVersionId: noticeID, impactAcknowledged: true)
        return await prepare(payload, id: id, kind: .createProfilePolicy, resourceID: nil, version: 0, expectedVersion: school.version)
    }
    @discardableResult
    func publishAfterConfirmation(_ policy: SchoolProfilePolicy) async -> Bool {
        guard canPublish(policy) else { return false }
        let id = UUID()
        return await prepare(SchoolEmptyProfileCommand(operationId: id), id: id, kind: .publishProfilePolicy, resourceID: policy.id, version: policy.version)
    }
    func canPublish(_ policy: SchoolProfilePolicy) -> Bool {
        canMutate && roles.contains("ADMIN") && policy.status == "DRAFT" && policies.contains(policy)
            && !isLoadingPublication && reviewingPolicyID == policy.id && publicationNotice?.status == "APPROVED"
            && publicationNotice?.noticeVersionId == policy.noticeVersionId
    }
    func preparePublication(_ policy: SchoolProfilePolicy) async {
        guard canMutate, roles.contains("ADMIN"), policy.status == "DRAFT", policies.contains(policy) else { return }
        reviewGeneration = UUID(); let review = reviewGeneration; let request = generation
        reviewingPolicyID = policy.id; publicationNotice = nil; isLoadingPublication = true; errorMessage = nil
        do {
            let exact = try await api.notice(schoolID: scope.schoolID, id: policy.noticeVersionId)
            guard review == reviewGeneration, request == generation else { return }
            guard exact.schoolId == scope.schoolID, exact.noticeVersionId == policy.noticeVersionId,
                  exact.status == "APPROVED" else { throw SchoolProfileFailure.invalidResponse }
            publicationNotice = exact; isLoadingPublication = false
        } catch {
            guard review == reviewGeneration, request == generation else { return }
            isLoadingPublication = false; fail(error)
        }
    }
    @discardableResult
    func saveProfileAfterConfirmation() async -> Bool {
        guard canSaveProfile, let profile, let policy = applicablePolicy else { return false }
        let id = UUID()
        var payload = draft.changes(from: profile, allowed: editableFields)
        payload["operationId"] = .text(id.uuidString); payload["policyVersionId"] = .text(policy.id.uuidString)
        return await prepare(payload, id: id, kind: .updateProfile, resourceID: profile.id, version: profile.version, routeID: learnerID)
    }
    @discardableResult
    func saveOnboarding(step: SchoolOnboardingStep, skipOptional: Bool) async -> Bool {
        guard canMutate, let onboarding, onboarding.status != "COMPLETED" else { return false }
        let id = UUID()
        let skipped = skipOptional ? ["PHOTO", "NOTIFICATIONS", "DEVICE"] : onboarding.skippedOptionalSteps
        let payload = SchoolOnboardingCommand(operationId: id, kind: onboarding.kind, currentStep: step,
            skippedOptionalSteps: skipped, policyVersionId: onboarding.policyVersionId)
        return await prepare(payload, id: id, kind: .saveOnboarding, resourceID: onboarding.id, version: onboarding.version)
    }
    @discardableResult
    func completeOnboardingAfterConfirmation() async -> Bool {
        guard canMutate, let onboarding, onboarding.status != "COMPLETED", onboarding.pendingActions.isEmpty else { return false }
        let id = UUID()
        return await prepare(SchoolCompleteOnboardingCommand(operationId: id, kind: onboarding.kind, policyVersionId: onboarding.policyVersionId),
            id: id, kind: .completeOnboarding, resourceID: onboarding.id, version: onboarding.version)
    }
    func retryPending() async { _ = await transmit(firstAttempt: false) }
    func verifyPending() async {
        guard canVerifyPending, let command = pending else { return }
        let request = generation; isBusy = true; errorMessage = nil
        do {
            let receipt = try await api.operation(schoolID: scope.schoolID, id: command.id)
            guard command.matches(receipt) else { throw SchoolProfileFailure.invalidResponse }
            try outbox.remove(command)
            guard request == generation else { return }
            pending = nil; pendingRequiresReview = false; isBusy = false
            successMessage = "La demande a été confirmée par l’école."
            await load(preserveDraft: false)
        } catch {
            guard request == generation else { return }; isBusy = false
            if error as? SchoolProfileFailure == .forbidden { await load(receiptRefused: true) }
            else { fail(error) }
        }
    }
    private func prepare<Value: Encodable>(_ payload: Value, id: UUID, kind: SchoolCommandKind,
        resourceID: UUID?, version: Int, routeID: UUID? = nil, expectedVersion: Int? = nil) async -> Bool {
        guard canMutate else { return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let command = PendingSchoolCommand(id: id, scope: scope, kind: kind, resourceVersion: version, createdAt: Date(),
                body: try encoder.encode(payload), resourceID: resourceID, routeResourceID: routeID, expectedVersion: expectedVersion)
            try outbox.save(command); pending = command; pendingRequiresReview = false
        } catch { storageAccessible = false; fail(error); return false }
        return await transmit(firstAttempt: true)
    }
    private func transmit(firstAttempt: Bool) async -> Bool {
        guard canRetryPending, let command = pending else { return false }
        let request = generation
        do { try outbox.save(command) } catch { storageAccessible = false; fail(error); return false }
        isBusy = true; errorMessage = nil; successMessage = nil
        do {
            let result = try await api.send(command)
            guard result.schoolID == scope.schoolID, result.version > command.resourceVersion,
                  command.resourceID.map({ $0 == result.id }) ?? true else { throw SchoolProfileFailure.invalidResponse }
            try outbox.remove(command)
            guard request == generation else { return true }
            pending = nil; pendingRequiresReview = false; isBusy = false
            successMessage = "Modification confirmée par l’école."
            await load(preserveDraft: command.kind != .updateProfile)
            return true
        } catch {
            if let failure = error as? SchoolProfileFailure, failure.permitsFreshCorrection {
                if firstAttempt {
                    do { try outbox.remove(command) }
                    catch { guard request == generation else { return false }; isBusy = false; storageAccessible = false; fail(error); return false }
                    guard request == generation else { return false }; pending = nil; needsReload = true
                } else { guard request == generation else { return false }; pendingRequiresReview = true }
            }
            guard request == generation else { return false }
            if error as? SchoolProfileFailure == .pendingCommand { pendingRequiresReview = true }
            isBusy = false; fail(error); return false
        }
    }
    private func ownsRoute(_ command: PendingSchoolCommand) -> Bool {
        switch command.kind {
        case .createProfilePolicy, .publishProfilePolicy: return isPolicyManagement && roles.contains("ADMIN")
        case .updateProfile: return command.routeResourceID == learnerID && learnerID != nil
        case .saveOnboarding, .completeOnboarding:
            guard let onboardingKind,
                  let payload = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any] else { return false }
            return payload["kind"] as? String == onboardingKind.rawValue
        default: return false
        }
    }
    private func validate(_ page: SchoolPage<SchoolProfilePolicy>) throws {
        guard page.items.allSatisfy({ SchoolProfileClient.valid($0, schoolID: scope.schoolID) }),
              Set(page.items.map(\.id)).count == page.items.count else { throw SchoolProfileFailure.invalidResponse }
    }
    private func fail(_ error: any Error) {
        let failure = error as? SchoolProfileFailure
        errorMessage = error is SchoolConfigurationFailure ? error.localizedDescription : (failure ?? .unavailable).localizedDescription
        if failure == .unauthorized || failure == .forbidden || failure == .notFound {
            generation = UUID(); school = nil; policies = []; profile = nil; notice = nil; readiness = nil; onboarding = nil
            draft = SchoolProfileDraft(); storageAccessible = false; isLoading = false; isBusy = false; nextCursor = nil
            accessFailure = failure
            reviewGeneration = UUID(); publicationNotice = nil; reviewingPolicyID = nil; isLoadingPublication = false
        }
    }
}
