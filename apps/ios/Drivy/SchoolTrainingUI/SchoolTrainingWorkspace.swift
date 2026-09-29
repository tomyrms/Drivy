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
    private(set) var lessonsLoaded = false
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
    var canOpenPedagogicalContent: Bool { (hasPedagogicalRole || membership.roles.contains("ADMIN")) && training != nil && !invalidated && !accessRevoked && !isLoading }
    var upcomingLessons: [SchoolLesson] { lessons.filter { $0.status == "PLANNED" }.sorted { $0.plannedStart < $1.plannedStart } }
    var pastLessons: [SchoolLesson] { lessons.filter { $0.status != "PLANNED" }.sorted { $0.plannedStart > $1.plannedStart } }
    var unobservedCompetencies: [SchoolCatalogCompetency] {
        guard let progress else { return [] }
        let ids = Set(progress.unobservedCompetencyIds)
        return competencies.filter { ids.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }
    }
    func invalidate() { invalidated = true; generation = UUID(); progressRequest = UUID(); clear(); isLoading = false; isLoadingMore = false }
    private func clear() { training = nil; lessons = []; nextCursor = nil; progress = nil; competencies = []; seenCursors = []; lessonsLoaded = false }

    /// `keepingCurrent` : relecture au retour d’une leçon ; ce qui est affiché reste visible jusqu’à la réponse.
    func load(keepingCurrent: Bool = false) async {
        guard !invalidated else { return }
        generation = UUID(); progressRequest = UUID(); let request = generation
        isLoading = !keepingCurrent || training == nil; isLoadingMore = false; errorMessage = nil
        if !keepingCurrent { progressError = nil }
        do {
            try await client.checkScope(scope, membership: membership)
            let value = try await client.reader.training(schoolID: scope.schoolID, id: trainingID)
            guard value.learnerId == learnerID else { throw SchoolAPIError.invalidResponse }
            guard request == generation, !invalidated else { return }
            training = value
        } catch {
            guard request == generation, !invalidated else { return }
            isLoading = false
            if error is CancellationError { return }
            if error as? SchoolAPIError == .notFound { clear() }
            fail(error); return
        }
        do {
            let page = try await client.lessons(schoolID: scope.schoolID, trainingID: trainingID, cursor: nil)
            guard page.items.allSatisfy({ $0.learnerId == learnerID }) else { throw SchoolAPIError.invalidResponse }
            guard request == generation, !invalidated else { return }
            lessons = page.items; nextCursor = page.nextCursor; seenCursors = []; lessonsLoaded = true
        } catch {
            guard request == generation, !invalidated else { return }
            if !(error is CancellationError) { fail(error) }
        }
        guard request == generation, !invalidated, !accessRevoked else { return }
        isLoading = false
        if hasPedagogicalRole { await loadProgress(keepingCurrent: keepingCurrent) }
    }
    func loadMore() async {
        guard !invalidated, !accessRevoked, !isLoading, !isLoadingMore, let cursor = nextCursor else { return }
        let request = generation; isLoadingMore = true; errorMessage = nil
        do {
            let page = try await client.lessons(schoolID: scope.schoolID, trainingID: trainingID, cursor: cursor)
            guard request == generation, !invalidated else { return }
            guard !seenCursors.contains(cursor), page.nextCursor != cursor, page.nextCursor.map({ !seenCursors.contains($0) }) ?? true,
                  page.items.allSatisfy({ $0.learnerId == learnerID }),
                  Set(lessons.map(\.id)).isDisjoint(with: Set(page.items.map(\.id))) else { throw SchoolAPIError.invalidResponse }
            seenCursors.insert(cursor); lessons.append(contentsOf: page.items); nextCursor = page.nextCursor; isLoadingMore = false
        } catch {
            guard request == generation else { return }
            isLoadingMore = false
            if !(error is CancellationError) { fail(error) }
        }
    }
    func loadProgress(keepingCurrent: Bool = false) async {
        guard !invalidated, !accessRevoked, hasPedagogicalRole, let training else { return }
        let request = generation; progressRequest = UUID(); let detailRequest = progressRequest
        progressError = nil
        if !keepingCurrent { progress = nil; competencies = [] }
        do {
            let value = try await client.reports.progress(schoolID: scope.schoolID, trainingID: trainingID)
            guard Set(value.unobservedCompetencyIds).count == value.unobservedCompetencyIds.count,
                  Set(value.items.map(\.id)).isDisjoint(with: Set(value.unobservedCompetencyIds)) else { throw SchoolAPIError.invalidResponse }
            guard request == generation, detailRequest == progressRequest, !invalidated else { return }
            progress = value
            // Le référentiel ne change pas d’une leçon à l’autre : il n’est relu qu’une fois.
            if competencies.isEmpty {
                let offerings = try await client.collect { try await self.client.catalog.offerings(schoolID: self.scope.schoolID, cursor: $0) }
                guard let offering = offerings.first(where: { $0.id == training.offeringId }) else { throw SchoolAPIError.notFound }
                let curricula = try await client.collect { try await self.client.catalog.curricula(schoolID: self.scope.schoolID, cursor: $0) }
                guard let curriculum = curricula.first(where: { $0.id == offering.curriculumVersionId }) else { throw SchoolAPIError.notFound }
                guard request == generation, detailRequest == progressRequest, !invalidated else { return }
                competencies = curriculum.competencies.sorted { $0.sortOrder < $1.sortOrder }
            }
        } catch {
            guard request == generation, detailRequest == progressRequest, !invalidated else { return }
            if error is CancellationError { return }
            if SchoolTrainingAccess.isRevoked(error) { fail(error) }
            else { progressError = SchoolTrainingAccess.message(error) }
        }
    }
    private func fail(_ error: Error) {
        errorMessage = SchoolTrainingAccess.message(error)
        if SchoolTrainingAccess.isRevoked(error) {
            clear(); accessRevoked = true; generation = UUID(); isLoading = false; isLoadingMore = false
        }
    }
}

/// Les onglets « Leçons » et « Progression » de l’élève montrent la même formation :
/// ils partagent un seul modèle au lieu de tout relire chacun.
@MainActor enum SchoolTrainingModelCache {
    private static var current: SchoolTrainingWorkspace?

    static func model(scope: SchoolCommandScope, membership: SchoolMembership, learnerID: UUID, trainingID: UUID,
                      client: SchoolTrainingClient) -> (model: SchoolTrainingWorkspace, isNew: Bool) {
        if let current, current.scope == scope, current.membership == membership, current.learnerID == learnerID,
           current.trainingID == trainingID, current.client.baseURL == client.baseURL, !current.accessRevoked {
            return (current, false)
        }
        // Un écran encore ouvert garde son propre modèle : il n’est pas invalidé ici.
        let value = SchoolTrainingWorkspace(scope: scope, membership: membership, learnerID: learnerID, trainingID: trainingID, client: client)
        current = value
        return (value, true)
    }
}
