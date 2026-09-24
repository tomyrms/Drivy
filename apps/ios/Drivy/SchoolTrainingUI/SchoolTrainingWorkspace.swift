import Foundation
import Observation

@MainActor @Observable final class SchoolTrainingWorkspace {
    let scope: SchoolCommandScope
    let membership: SchoolMembership
    let learnerID: UUID
    let trainingID: UUID
    let client: SchoolTrainingClient
    private(set) var training: SchoolTraining?
    private(set) var lessons: [SchoolLesson] = []
    private(set) var nextCursor: String?
    private(set) var progress: SchoolReportProgress?
    private(set) var competencies: [SchoolCatalogCompetency] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var progressError: String?
    private(set) var accessRevoked = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var progressRequest = UUID()
    @ObservationIgnored private var seenCursors = Set<String>()
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, membership: SchoolMembership, learnerID: UUID, trainingID: UUID, client: SchoolTrainingClient) {
        self.scope = scope; self.membership = membership; self.learnerID = learnerID; self.trainingID = trainingID; self.client = client
    }
    var hasPedagogicalRole: Bool { membership.roles.contains("INSTRUCTOR") || membership.roles.contains("LEARNER") }
    // L’ouverture déclenche sa propre lecture autorisée. AP58 n’est pas une permission
    // pour AP55/56 : une indisponibilité de la progression ne doit pas masquer les bilans.
    var canOpenPedagogicalContent: Bool { hasPedagogicalRole && training != nil && !invalidated && !accessRevoked && !isLoading }
    var publishedLessons: [SchoolLesson] { lessons.filter { $0.currentPublishedRevisionId != nil }.sorted { $0.plannedStart > $1.plannedStart } }
    var upcomingLessons: [SchoolLesson] { lessons.filter { $0.status == "PLANNED" }.sorted { $0.plannedStart < $1.plannedStart } }
    var pastLessons: [SchoolLesson] { lessons.filter { $0.status != "PLANNED" }.sorted { $0.plannedStart > $1.plannedStart } }
    var unobservedCompetencies: [SchoolCatalogCompetency] {
        guard let progress else { return [] }
        let ids = Set(progress.unobservedCompetencyIds)
        return competencies.filter { ids.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }
    }
    func invalidate() { invalidated = true; generation = UUID(); progressRequest = UUID(); clear(); isLoading = false; isLoadingMore = false }
    private func clear() { training = nil; lessons = []; nextCursor = nil; progress = nil; competencies = []; seenCursors = [] }

    func load() async {
        guard !invalidated else { return }
        generation = UUID(); let request = generation
        clear(); isLoading = true; errorMessage = nil; progressError = nil
        do {
            try await client.checkScope(scope, membership: membership)
            let value = try await client.reader.training(schoolID: scope.schoolID, id: trainingID)
            guard value.learnerId == learnerID else { throw SchoolAPIError.invalidResponse }
            let page = try await client.lessons(schoolID: scope.schoolID, trainingID: trainingID, cursor: nil)
            guard page.items.allSatisfy({ $0.learnerId == learnerID }) else { throw SchoolAPIError.invalidResponse }
            guard request == generation, !invalidated else { return }
            training = value; lessons = page.items; nextCursor = page.nextCursor; isLoading = false
            if hasPedagogicalRole { await loadProgress() }
        } catch {
            guard request == generation, !invalidated else { return }
            isLoading = false; fail(error)
        }
    }
    func loadMore() async {
        guard !invalidated, !accessRevoked, !isLoading, !isLoadingMore, let cursor = nextCursor else { return }
        let request = generation; isLoadingMore = true; errorMessage = nil
        do {
            let page = try await client.lessons(schoolID: scope.schoolID, trainingID: trainingID, cursor: cursor)
            guard request == generation, !invalidated else { return }
            guard seenCursors.insert(cursor).inserted, page.nextCursor.map({ !seenCursors.contains($0) }) ?? true,
                  page.items.allSatisfy({ $0.learnerId == learnerID }),
                  Set(lessons.map(\.id)).isDisjoint(with: Set(page.items.map(\.id))) else { throw SchoolAPIError.invalidResponse }
            lessons.append(contentsOf: page.items); nextCursor = page.nextCursor; isLoadingMore = false
        } catch { guard request == generation else { return }; isLoadingMore = false; fail(error) }
    }
    func loadProgress() async {
        guard !invalidated, !accessRevoked, hasPedagogicalRole, let training else { return }
        let request = generation; progressRequest = UUID(); let detailRequest = progressRequest
        progressError = nil; progress = nil; competencies = []
        do {
            let value = try await client.reports.progress(schoolID: scope.schoolID, trainingID: trainingID)
            guard Set(value.unobservedCompetencyIds).count == value.unobservedCompetencyIds.count,
                  Set(value.items.map(\.id)).isDisjoint(with: Set(value.unobservedCompetencyIds)) else { throw SchoolAPIError.invalidResponse }
            guard request == generation, detailRequest == progressRequest, !invalidated else { return }
            progress = value
            let offerings = try await client.collect { try await self.client.catalog.offerings(schoolID: self.scope.schoolID, cursor: $0) }
            guard let offering = offerings.first(where: { $0.id == training.offeringId }) else { throw SchoolAPIError.notFound }
            let curricula = try await client.collect { try await self.client.catalog.curricula(schoolID: self.scope.schoolID, cursor: $0) }
            guard let curriculum = curricula.first(where: { $0.id == offering.curriculumVersionId }) else { throw SchoolAPIError.notFound }
            guard request == generation, detailRequest == progressRequest, !invalidated else { return }
            competencies = curriculum.competencies.sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            guard request == generation, detailRequest == progressRequest, !invalidated else { return }
            if SchoolTrainingAccess.isRevoked(error) { fail(error) }
            else { progressError = SchoolTrainingAccess.message(error) }
        }
    }
    private func fail(_ error: Error) {
        errorMessage = SchoolTrainingAccess.message(error)
        if SchoolTrainingAccess.isRevoked(error) { clear(); accessRevoked = true; generation = UUID() }
    }
}

/// A separate creation flow lets an assigned instructor use AP23 without requesting the admin-only members list.
@MainActor @Observable final class SchoolTrainingCreationWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let membership: SchoolMembership
    let learner: SchoolLearner
    let client: SchoolTrainingClient
    private(set) var offerings: [SchoolOffering] = []
    private(set) var school: SchoolDetails?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var createdTrainingID: UUID?
    private(set) var accessRevoked = false
    private(set) var pendingRequiresReview = false
    var selectedOfferingID: UUID?
    var usesStartDate = false
    var startDate = Date()
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var storageAvailable = false

    init(scope: SchoolCommandScope, membership: SchoolMembership, learner: SchoolLearner, client: SchoolTrainingClient,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.membership = membership; self.learner = learner; self.client = client; self.outbox = outbox
    }
    var selectedOffering: SchoolOffering? { offerings.first { $0.id == selectedOfferingID } }
    var canCreate: Bool { !invalidated && !accessRevoked && !isLoading && !isBusy && storageAvailable && pending == nil
        && school?.status == "ACTIVE" && selectedOffering != nil && createdTrainingID == nil }
    var canRetry: Bool { !invalidated && !accessRevoked && !isBusy && !isLoading && !pendingRequiresReview
        && pending?.scope == scope && pending?.kind == .createTraining && pending?.routeResourceID == learner.id }
    func invalidate() { invalidated = true; generation = UUID(); offerings = []; school = nil; pending = nil; isBusy = false; isLoading = false }
    func load() async {
        guard !invalidated, !isBusy else { return }
        generation = UUID(); let request = generation
        isLoading = true; errorMessage = nil; storageAvailable = false
        var storageError: String?
        do { pending = try outbox.pending(for: scope); storageAvailable = true }
        catch { storageError = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            try await client.checkScope(scope, membership: membership)
            guard membership.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) }) else { throw SchoolAPIError.forbidden }
            let currentLearner = try await client.reader.learner(schoolID: scope.schoolID, id: learner.id)
            guard currentLearner.archivedAt == nil else { throw SchoolCatalogFailure.rejected("Ce dossier est archivé.") }
            let school = try await client.reader.school(id: scope.schoolID)
            let offerings = try await client.collect { try await self.client.catalog.offerings(schoolID: self.scope.schoolID, cursor: $0) }
            let curricula = try await client.collect { try await self.client.catalog.curricula(schoolID: self.scope.schoolID, cursor: $0) }
            let policies = try await client.collect { try await self.client.catalog.policies(schoolID: self.scope.schoolID, cursor: $0) }
            let current = Dictionary(grouping: offerings, by: \.offeringKey).values.compactMap { $0.max { $0.version < $1.version } }
            let approvedCurricula = Set(curricula.filter(\.approved).map(\.id))
            let approvedPolicies = Set(policies.filter(\.approved).map(\.id))
            guard request == generation, !invalidated else { return }
            self.school = school
            self.offerings = current.filter { $0.enabled && approvedCurricula.contains($0.curriculumVersionId) && approvedPolicies.contains($0.policyVersionId) }
                .sorted { ($0.categoryCode, $0.offeringKey) < ($1.categoryCode, $1.offeringKey) }
            if !self.offerings.contains(where: { $0.id == selectedOfferingID }) { selectedOfferingID = nil }
            isLoading = false; errorMessage = storageError
        } catch { guard request == generation else { return }; isLoading = false; fail(error) }
    }
    func create() async -> Bool {
        guard canCreate, let offering = selectedOffering, let school else { return false }
        do {
            let operationID = UUID()
            let value = SchoolCreateTraining(operationId: operationID, learnerId: learner.id, offeringId: offering.id,
                startedOn: usesStartDate ? SchoolCatalogFormatting.civilDate(startDate, timeZone: school.timeZone) : nil)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let command = PendingSchoolCommand(id: operationID, scope: scope, kind: .createTraining, resourceVersion: 0,
                createdAt: Date(), body: try encoder.encode(value), routeResourceID: learner.id)
            try outbox.save(command); pending = command; pendingRequiresReview = false
        } catch { storageAvailable = false; fail(error); return false }
        return await transmit(firstAttempt: true)
    }
    func retry() async { _ = await transmit(firstAttempt: false) }
    func verify() async {
        guard !invalidated, !accessRevoked, !isBusy, let command = pending, command.scope.belongsToWorkspace(scope) else { return }
        let request = generation; isBusy = true; errorMessage = nil
        do {
            let receipt = try await client.catalog.operation(schoolID: scope.schoolID, id: command.id)
            guard command.matches(receipt) else { throw SchoolCatalogFailure.invalidResponse }
            try outbox.remove(command)
            guard request == generation, !invalidated else { return }
            pending = nil; isBusy = false; pendingRequiresReview = false
            if command.kind == .createTraining && command.routeResourceID == learner.id { confirm(receipt.resourceId) }
            else { successMessage = "La demande en attente est confirmée. Vous pouvez reprendre." }
        } catch { guard request == generation else { return }; isBusy = false; fail(error) }
    }
    private func transmit(firstAttempt: Bool) async -> Bool {
        guard canRetry, let command = pending else { return false }
        let request = generation; isBusy = true; errorMessage = nil
        do {
            try outbox.save(command)
            let result = try await client.catalog.send(command)
            guard case .training(let training) = result else { throw SchoolCatalogFailure.invalidResponse }
            try outbox.remove(command)
            guard request == generation, !invalidated else { return true }
            pending = nil; isBusy = false; confirm(training.id); return true
        } catch {
            guard request == generation, !invalidated else { return false }
            if let failure = error as? SchoolCatalogFailure, failure.permitsFreshCorrection {
                if firstAttempt {
                    do { try outbox.remove(command); pending = nil; school = nil }
                    catch { storageAvailable = false; isBusy = false; fail(error); return false }
                } else { pendingRequiresReview = true }
            }
            isBusy = false; fail(error); return false
        }
    }
    private func confirm(_ trainingID: UUID) {
        createdTrainingID = trainingID
        // AP23 never grants an assignment. A successful creation may remain unreadable to its instructor author.
        successMessage = "La formation a été créée. L’administration peut maintenant affecter le moniteur à cette formation."
    }
    private func fail(_ error: Error) {
        errorMessage = SchoolTrainingAccess.message(error)
        if SchoolTrainingAccess.isRevoked(error) { accessRevoked = true; offerings = []; school = nil; generation = UUID() }
    }
}
