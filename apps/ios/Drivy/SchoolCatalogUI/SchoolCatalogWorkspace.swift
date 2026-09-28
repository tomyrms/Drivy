import Foundation
import Observation

@MainActor @Observable final class SchoolCatalogWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let learner: SchoolLearner?
    private(set) var school: SchoolDetails?
    private(set) var offerings: [SchoolOffering] = []
    private(set) var curricula: [SchoolCurriculum] = []
    private(set) var policies: [SchoolCatalogPolicy] = []
    private(set) var members: [SchoolMember] = []
    private(set) var trainings: [SchoolTraining] = []
    private(set) var assignments: [SchoolAssignment] = []
    private(set) var selectedTraining: SchoolTraining?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var accessFailure: SchoolCatalogFailure?
    private(set) var pendingRequiresReview = false
    private(set) var needsReload = true
    @ObservationIgnored private let api: any SchoolCatalogAPI
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var assignmentRequest = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var storageAccessible = false

    init(scope: SchoolCommandScope, learner: SchoolLearner? = nil, api: any SchoolCatalogAPI,
        outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.learner = learner; self.api = api; self.outbox = outbox
    }
    var canMutate: Bool { !invalidated && !isBusy && !isLoading && !needsReload && pending == nil && storageAccessible && school?.status == "ACTIVE" }
    var instructors: [SchoolMember] { members.filter { $0.status == "ACTIVE" && $0.roles.contains("INSTRUCTOR") } }
    var currentOfferings: [SchoolOffering] {
        Dictionary(grouping: offerings, by: \.offeringKey).values.compactMap { $0.max { $0.version < $1.version } }
            .sorted { ($0.categoryCode, $0.offeringKey) < ($1.categoryCode, $1.offeringKey) }
    }
    var availableOfferings: [SchoolOffering] { currentOfferings.filter(\.enabled) }
    var canRetry: Bool {
        guard let pending else { return false }
        guard pending.kind.isCatalog, pending.scope == scope, !pendingRequiresReview, !invalidated, !isBusy, !isLoading else { return false }
        switch pending.kind {
        case .createTraining: return learner?.id == pending.routeResourceID
        case .createAssignment: return selectedTraining?.id == pending.routeResourceID
        case .createOffering, .createCurriculum, .createCatalogPolicy: return learner == nil
        default: return false
        }
    }
    var canVerify: Bool { pending != nil && !invalidated && !isBusy && !isLoading }
    var pendingSummary: String {
        guard let pending else { return "" }
        switch pending.kind {
        case .createTraining: return "Création de formation"
        case .createAssignment: return "Affectation d’un moniteur"
        case .createOffering: return "Création d’une version d’offre"
        case .createCurriculum: return "Création d’un référentiel"
        case .createCatalogPolicy: return "Création d’une procédure"
        default: return "Demande dans cette école"
        }
    }
    func invalidate() {
        invalidated = true; generation = UUID(); assignmentRequest = UUID()
        school = nil; offerings = []; curricula = []; policies = []; members = []; trainings = []; assignments = []
        selectedTraining = nil; pending = nil; errorMessage = nil; successMessage = nil; isLoading = false; isBusy = false
    }
    func load() async {
        guard !invalidated, !isBusy else { return }
        generation = UUID(); let request = generation
        isLoading = true; needsReload = true; errorMessage = nil; storageAccessible = false
        var storageError: String?
        do { pending = try outbox.pending(for: scope); storageAccessible = true }
        catch { storageError = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            let school = try await api.school(id: scope.schoolID)
            let offerings = try await collect { try await self.api.offerings(schoolID: self.scope.schoolID, cursor: $0) }
            let curricula = try await collect { try await self.api.curricula(schoolID: self.scope.schoolID, cursor: $0) }
            let policies = try await collect { try await self.api.policies(schoolID: self.scope.schoolID, cursor: $0) }
            let members = try await collect { try await self.api.members(schoolID: self.scope.schoolID, cursor: $0) }
            guard let actor = members.first(where: { $0.id == scope.membershipID }), actor.personId == scope.personID,
                  actor.status == "ACTIVE", actor.roles.contains("ADMIN"), actor.accessEpoch == scope.accessEpoch else { throw SchoolCatalogFailure.forbidden }
            var trainings: [SchoolTraining] = []
            if let learner {
                trainings = try await collect { try await self.api.trainings(schoolID: self.scope.schoolID, learnerID: learner.id, cursor: $0) }
            }
            guard request == generation else { return }
            guard school.id == scope.schoolID else { throw SchoolCatalogFailure.invalidResponse }
            self.school = school; self.offerings = offerings; self.curricula = curricula; self.policies = policies
            self.members = members; self.trainings = trainings; isLoading = false; needsReload = false
            errorMessage = storageError
            if let selectedTraining, let updated = trainings.first(where: { $0.id == selectedTraining.id }) {
                await selectTraining(updated)
            } else { self.selectedTraining = nil; assignments = [] }
        } catch { guard request == generation else { return }; isLoading = false; fail(error) }
    }
    func selectTraining(_ training: SchoolTraining) async {
        guard !invalidated, training.schoolId == scope.schoolID, training.learnerId == learner?.id else { return }
        assignmentRequest = UUID(); let request = assignmentRequest; let scopeRequest = generation
        selectedTraining = training; assignments = []; isLoading = true; errorMessage = nil
        do {
            let records = try await collect { try await self.api.assignments(schoolID: self.scope.schoolID, trainingID: training.id, cursor: $0) }
            guard request == assignmentRequest, scopeRequest == generation else { return }
            assignments = records; isLoading = false
        } catch { guard request == assignmentRequest, scopeRequest == generation else { return }; isLoading = false; fail(error) }
    }
    func createTraining(offeringID: UUID, startedOn: String?) async -> Bool {
        guard let learner, learner.archivedAt == nil, availableOfferings.contains(where: { $0.id == offeringID }) else { return false }
        let id = UUID()
        return await prepare(SchoolCreateTraining(operationId: id, learnerId: learner.id, offeringId: offeringID, startedOn: startedOn),
            id: id, kind: .createTraining, routeID: learner.id)
    }
    func createAssignment(memberID: UUID, from: Date, until: Date?) async -> Bool {
        guard let selectedTraining, selectedTraining.status == "ACTIVE", instructors.contains(where: { $0.id == memberID }), until.map({ $0 > from }) ?? true else { return false }
        let formatter = ISO8601DateFormatter(); let id = UUID()
        return await prepare(SchoolCreateAssignment(operationId: id, instructorMembershipId: memberID,
            validFrom: formatter.string(from: from), validUntil: until.map { formatter.string(from: $0) }),
            id: id, kind: .createAssignment, routeID: selectedTraining.id)
    }
    func createOffering(_ draft: SchoolOfferingDraft) async -> Bool {
        guard draft.isValid, let curriculumID = draft.curriculumID, let policyID = draft.policyID,
              let duration = Int(draft.duration), let cents = SchoolCatalogFormatting.cents(draft.price) else { return false }
        let id = UUID()
        return await prepare(SchoolCreateOffering(operationId: id, offeringKey: draft.key.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryCode: draft.category.trimmingCharacters(in: .whitespacesAndNewlines), curriculumVersionId: curriculumID,
            enabled: draft.enabled, defaultDurationMinutes: duration, defaultPriceCents: cents, policyVersionId: policyID), id: id, kind: .createOffering)
    }
    func createCurriculum(_ draft: SchoolCurriculumDraft) async -> Bool {
        guard draft.isValid else { return false }
        let id = UUID()
        let competencies = draft.competencies.enumerated().map { index, value in
            SchoolCreateCompetency(key: value.key.trimmed, label: value.label.trimmed, description: value.explanation.trimmed, sortOrder: index)
        }
        return await prepare(SchoolCreateCurriculum(operationId: id, categoryCode: draft.category.trimmed,
            approved: draft.approved, approvalReason: draft.reason.trimmed, competencies: competencies), id: id, kind: .createCurriculum)
    }
    func createPolicy(_ draft: SchoolCatalogPolicyDraft) async -> Bool {
        guard draft.isValid else { return false }
        let id = UUID()
        return await prepare(SchoolCreateCatalogPolicy(operationId: id, categoryCode: draft.category.trimmed,
            procedureText: draft.procedure.trimmed, cancellationPolicyText: draft.cancellation.trimmed,
            sourceUrls: draft.urls, approved: draft.approved, approvalReason: draft.reason.trimmed), id: id, kind: .createCatalogPolicy)
    }
    func retryPending() async { _ = await transmit(firstAttempt: false) }
    func verifyPending() async {
        guard canVerify, let command = pending else { return }
        let request = generation; isBusy = true; errorMessage = nil
        do {
            let receipt = try await api.operation(schoolID: scope.schoolID, id: command.id)
            guard command.matches(receipt) else { throw SchoolCatalogFailure.invalidResponse }
            try outbox.remove(command)
            guard request == generation else { return }
            pending = nil; pendingRequiresReview = false; isBusy = false
            successMessage = "La demande est confirmée par l’école."
            await load()
            if command.kind == .createTraining, let training = trainings.first(where: { $0.id == receipt.resourceId }) { await selectTraining(training) }
        } catch { guard request == generation else { return }; isBusy = false; fail(error) }
    }
    private func prepare<Value: Encodable>(_ value: Value, id: UUID, kind: SchoolCommandKind, routeID: UUID? = nil) async -> Bool {
        guard canMutate else { return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let body = try encoder.encode(value)
            guard body.count <= 200_000 else {
                errorMessage = "Ce contenu est trop volumineux pour un enregistrement sur cet appareil. Raccourcissez les descriptions avant de confirmer."
                return false
            }
            let command = PendingSchoolCommand(id: id, scope: scope, kind: kind, resourceVersion: 0, createdAt: Date(),
                body: body, routeResourceID: routeID)
            try outbox.save(command); pending = command; pendingRequiresReview = false
        } catch { storageAccessible = false; fail(error); return false }
        return await transmit(firstAttempt: true)
    }
    private func transmit(firstAttempt: Bool) async -> Bool {
        guard canRetry, let command = pending else { return false }
        let request = generation
        do { try outbox.save(command) } catch { storageAccessible = false; fail(error); return false }
        isBusy = true; errorMessage = nil; successMessage = nil
        do {
            let result = try await api.send(command)
            guard result.schoolID == scope.schoolID, result.version > command.resourceVersion,
                  command.resourceID.map({ $0 == result.id }) ?? true else { throw SchoolCatalogFailure.invalidResponse }
            try outbox.remove(command)
            guard request == generation else { return true }
            pending = nil; pendingRequiresReview = false; isBusy = false
            successMessage = command.kind == .createTraining ? "Formation créée. Vous pouvez maintenant affecter un moniteur." : "Enregistrement confirmé par l’école."
            await load()
            if case .training(let training) = result { await selectTraining(training) }
            return true
        } catch {
            if let failure = error as? SchoolCatalogFailure, failure.permitsFreshCorrection {
                if firstAttempt {
                    do { try outbox.remove(command) }
                    catch { guard request == generation else { return false }; isBusy = false; storageAccessible = false; fail(error); return false }
                    guard request == generation else { return false }; pending = nil; needsReload = true
                } else { guard request == generation else { return false }; pendingRequiresReview = true }
            }
            guard request == generation else { return false }
            if error as? SchoolCatalogFailure == .pending { pendingRequiresReview = true }
            isBusy = false; fail(error); return false
        }
    }
    private func collect<Value: SchoolCatalogRecord>(_ fetch: (String?) async throws -> SchoolPage<Value>) async throws -> [Value] {
        let request = generation
        var records: [Value] = []; var cursor: String?; var seen: Set<String> = []
        repeat {
            guard !invalidated, request == generation, seen.count < 100 else { throw SchoolCatalogFailure.invalidResponse }
            let page = try await fetch(cursor)
            guard request == generation else { throw SchoolCatalogFailure.invalidResponse }
            guard page.items.allSatisfy({ $0.schoolId == scope.schoolID }),
                  Set(records.map(\.id)).isDisjoint(with: Set(page.items.map(\.id))) else { throw SchoolCatalogFailure.invalidResponse }
            records.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor { guard seen.insert(cursor).inserted else { throw SchoolCatalogFailure.invalidResponse } }
        } while cursor != nil
        return records
    }
    private func fail(_ error: any Error) {
        let failure = error as? SchoolCatalogFailure
        errorMessage = error is SchoolConfigurationFailure ? error.localizedDescription : (failure ?? .unavailable).localizedDescription
        if failure == .unauthorized || failure == .forbidden {
            generation = UUID(); assignmentRequest = UUID(); school = nil; offerings = []; curricula = []; policies = []
            members = []; trainings = []; assignments = []; selectedTraining = nil; accessFailure = failure
            needsReload = true; storageAccessible = false; isLoading = false; isBusy = false
        }
    }
}

extension String { fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
struct SchoolOfferingDraft {
    var key = "", category = "", duration = "", price = ""
    var curriculumID: UUID?, policyID: UUID?
    var enabled = false
    var isValid: Bool { !key.trimmed.isEmpty && key.count <= 80 && !category.trimmed.isEmpty && category.count <= 30
        && curriculumID != nil && policyID != nil && Int(duration).map({ (1...480).contains($0) }) == true
        && SchoolCatalogFormatting.cents(price) != nil }
}
struct SchoolCompetencyDraft: Identifiable {
    let id = UUID()
    var key = "", label = "", explanation = ""
    var isValid: Bool { !key.trimmed.isEmpty && key.count <= 80 && !label.trimmed.isEmpty && label.count <= 200 && !explanation.trimmed.isEmpty && explanation.count <= 4000 }
}
struct SchoolCurriculumDraft {
    var category = "", reason = ""
    var approved = false
    var competencies = [SchoolCompetencyDraft()]
    var isValid: Bool { !category.trimmed.isEmpty && category.count <= 30 && !reason.trimmed.isEmpty && reason.count <= 1000
        && !competencies.isEmpty && competencies.count <= 200 && competencies.allSatisfy(\.isValid)
        && Set(competencies.map { $0.key.trimmed }).count == competencies.count }
}
struct SchoolCatalogPolicyDraft {
    var category = "", procedure = "", cancellation = "", sources = "", reason = ""
    var approved = false
    var urls: [String] { sources.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty } }
    var isValid: Bool { !category.trimmed.isEmpty && category.count <= 30 && !procedure.trimmed.isEmpty && procedure.count <= 4000
        && !cancellation.trimmed.isEmpty && cancellation.count <= 4000 && !reason.trimmed.isEmpty && reason.count <= 1000
        && urls.count <= 30 && urls.allSatisfy { value in
            guard let url = URL(string: value) else { return false }
            return value.count <= 2048 && ["https", "http"].contains(url.scheme ?? "") && url.host != nil && url.user == nil && url.password == nil
        } }
}
