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
    private(set) var isLoadingHistory = false
    private(set) var lessonsLoaded = false
    private(set) var errorMessage: String?
    private(set) var progressError: String?
    private(set) var accessRevoked = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var progressRequest = UUID()
    @ObservationIgnored private var seenCursors = Set<String>()
    @ObservationIgnored private var historyRequested = false
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private(set) var invalidated = false

    init(scope: SchoolCommandScope, membership: SchoolMembership, learnerID: UUID, trainingID: UUID, client: SchoolTrainingClient) {
        self.scope = scope; self.membership = membership; self.learnerID = learnerID; self.trainingID = trainingID; self.client = client
    }
    /// Lit la progression de la formation : moniteur, élève, ou administration de l’école (lecture seule, droit relu par le serveur).
    var hasPedagogicalRole: Bool { membership.roles.contains("INSTRUCTOR") || membership.roles.contains("LEARNER") || membership.roles.contains("ADMIN") }
    // L’ouverture déclenche sa propre lecture autorisée. AP58 n’est pas une permission
    // pour AP55/56 : une indisponibilité de la progression ne doit pas masquer les bilans.
    var canOpenPedagogicalContent: Bool { hasPedagogicalRole && training != nil && !invalidated && !accessRevoked && !isLoading }
    var upcomingLessons: [SchoolLesson] { upcomingLessons(at: Date()) }
    /// Une leçon passée sans constat reste à terminer ; elle ne prend pas la place du prochain rendez-vous.
    func upcomingLessons(at now: Date) -> [SchoolLesson] {
        lessons.filter { $0.status == "PLANNED" && ($0.endsAt.map { $0 > now } ?? false) }
            .sorted { $0.plannedStart < $1.plannedStart }
    }
    var pastLessons: [SchoolLesson] { lessons.filter { $0.status != "PLANNED" }.sorted { $0.plannedStart > $1.plannedStart } }
    var unobservedCompetencies: [SchoolCatalogCompetency] {
        guard let progress else { return [] }
        let ids = Set(progress.unobservedCompetencyIds)
        return competencies.filter { ids.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }
    }
    /// Retour sur l’écran : le modèle est partagé et gardé en mémoire, donc relu à chaque affichage
    /// (un bilan enregistré ailleurs change la progression). L’affichage courant reste visible jusqu’à la réponse.
    func refreshOnAppear() async { await load(keepingCurrent: true) }
    func invalidate() {
        invalidated = true; generation = UUID(); progressRequest = UUID(); cancelHistory()
        clear(); isLoading = false; isLoadingMore = false
    }
    private func cancelHistory() { historyTask?.cancel(); historyTask = nil; isLoadingHistory = false }
    private func clear() { training = nil; lessons = []; nextCursor = nil; progress = nil; competencies = []; seenCursors = []; lessonsLoaded = false }

    /// `keepingCurrent` : relecture au retour d’une leçon ; ce qui est affiché reste visible jusqu’à la réponse.
    func load(keepingCurrent: Bool = false) async {
        guard !invalidated else { return }
        generation = UUID(); progressRequest = UUID(); let request = generation
        cancelHistory()
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
        if hasPedagogicalRole { await loadProgress() }
        if historyRequested { await loadHistory() }
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
    /// Les filtres de période portent sur l'historique autorisé complet, jamais sur la seule première page.
    func loadHistory() async {
        historyRequested = true
        guard !isLoading, !invalidated, !accessRevoked else { return }
        if let historyTask { await historyTask.value; return }
        let request = generation
        isLoadingHistory = true
        // Le choix d'un autre mois ou la fermeture du sélecteur ne doit pas interrompre l'historique partagé.
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.fetchHistory(request: request)
        }
        historyTask = task
        await task.value
        guard request == generation else { return }
        historyTask = nil; isLoadingHistory = false
    }
    private func fetchHistory(request: UUID) async {
        while let cursor = nextCursor, request == generation, !invalidated, !accessRevoked, !Task.isCancelled {
            guard lessons.count < 10_000 else {
                errorMessage = "L’historique est trop long pour être chargé en une fois. Affiche les autres leçons pour continuer."
                return
            }
            await loadMore()
            // Une erreur ou une lecture concurrente ne doit pas provoquer une boucle.
            if nextCursor == cursor || errorMessage != nil { return }
        }
    }
    func loadProgress(keepingCurrent: Bool = true) async {
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
            // Un refus sur la seule progression ne ferme pas le dossier : seule une session perdue le fait.
            if error as? SchoolAPIError == .unauthorized || error as? SchoolAPIError == .identityNotLinked
                || error as? SchoolReportFailure == .unauthorized || error as? SchoolCatalogFailure == .unauthorized { fail(error) }
            else {
                // Une panne conserve la lecture ; un refus retire immédiatement la projection concernée.
                if SchoolTrainingAccess.isRevoked(error) || error as? SchoolAPIError == .notFound
                    || error as? SchoolReportFailure == .notFound {
                    progress = nil; competencies = []
                }
                progressError = SchoolTrainingAccess.message(error)
            }
        }
    }
    private func fail(_ error: Error) {
        errorMessage = SchoolTrainingAccess.message(error)
        if SchoolTrainingAccess.isRevoked(error) {
            clear(); accessRevoked = true; generation = UUID(); cancelHistory(); isLoading = false; isLoadingMore = false
        }
    }
}

/// Les leçons d’un élève pour les formations montrées. Le serveur ne lit les leçons que par formation, de la plus
/// ancienne à la plus récente : ces lectures sont fusionnées ici, sans route ni droit supplémentaire.
@MainActor struct SchoolLessonFeed {
    let models: [SchoolTrainingWorkspace]

    var lessons: [SchoolLesson] { Self.merged(models.map { (lessons: $0.lessons, hasMore: $0.nextCursor != nil) }) }

    /// Tant qu’une formation a d’autres pages, rien n’est montré au-delà de sa dernière leçon lue : la liste est celle
    /// qu’une lecture unique aurait donnée, sans leçon manquante au milieu d’un mois déjà affiché.
    static func merged(_ sources: [(lessons: [SchoolLesson], hasMore: Bool)]) -> [SchoolLesson] {
        let all = sources.flatMap { $0.lessons }
        guard let limit = sources.filter({ $0.hasMore }).map({ lastStart($0.lessons) }).min() else { return all }
        return all.filter { ($0.startsAt ?? .distantPast) <= limit }
    }
    private static func lastStart(_ lessons: [SchoolLesson]) -> Date { lessons.compactMap(\.startsAt).max() ?? .distantPast }

    var hasLessons: Bool { models.contains { !$0.lessons.isEmpty } }
    var hasMore: Bool { models.contains { $0.nextCursor != nil } }
    /// Une liste vide ne se dit que lorsque chaque formation a répondu.
    var allRead: Bool { models.allSatisfy { $0.lessonsLoaded } }
    var isLoading: Bool { models.contains { $0.isLoading } }
    /// Première lecture : aucune liste partielle tant qu’une formation n’a pas répondu.
    var isLoadingFirstPage: Bool { models.contains { $0.isLoading && !$0.lessonsLoaded } }
    var isLoadingMore: Bool { models.contains { $0.isLoadingMore } }
    var isLoadingHistory: Bool { models.contains { $0.isLoadingHistory } }

    func model(for lesson: SchoolLesson) -> SchoolTrainingWorkspace? { models.first { $0.trainingID == lesson.trainingId } }

    /// Seules les formations qui retiennent la suite avancent d’une page.
    func loadMore() async {
        let pending = models.filter { $0.nextCursor != nil }
        guard let limit = pending.map({ Self.lastStart($0.lessons) }).min() else { return }
        await Self.together(pending.filter { Self.lastStart($0.lessons) == limit }) { await $0.loadMore() }
    }
    func loadHistory() async { await Self.together(models) { await $0.loadHistory() } }
    /// Relecture silencieuse : ce qui est affiché reste visible jusqu’à chaque réponse.
    func reload() async { await Self.together(models) { await $0.load(keepingCurrent: true) } }

    static func together(_ models: [SchoolTrainingWorkspace],
                         _ work: @escaping @MainActor @Sendable (SchoolTrainingWorkspace) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            for model in models { group.addTask { await work(model) } }
        }
    }
}

/// Le nom d’un permis dans un filtre, un titre ou une ligne de leçon.
enum SchoolPermitName {
    /// La formation en cours d’abord ; l’ordre du dossier départage.
    static func ordered(_ trainings: [SchoolTraining]) -> [SchoolTraining] {
        trainings.filter { $0.status == "ACTIVE" } + trainings.filter { $0.status != "ACTIVE" }
    }

    /// Deux formations de même catégorie se distinguent par leur année de début.
    static func names(_ trainings: [SchoolTraining]) -> [UUID: String] {
        let counts = Dictionary(trainings.map { ($0.categoryCode, 1) }, uniquingKeysWith: +)
        var result: [UUID: String] = [:]
        for training in trainings {
            var name = "Permis \(training.categoryCode)"
            if (counts[training.categoryCode] ?? 0) > 1, let year = training.startedOn?.prefix(4), year.count == 4 {
                name += " · \(year)"
            }
            result[training.id] = name
        }
        return result
    }

    /// Sous le nom de l’élève : ses permis en une ligne. Seul un état inhabituel est précisé.
    static func summary(_ trainings: [SchoolTraining]) -> String? {
        guard trainings.count > 1 else { return trainings.first.map { "Permis \($0.categoryCode)" } }
        let parts = trainings.map { training in
            training.status == "ACTIVE" ? training.categoryCode
                : "\(training.categoryCode) (\(SchoolPresentation.trainingStatus(training.status).lowercased()))"
        }
        return "Permis " + parts.joined(separator: ", ")
    }
}

/// Les pages « Leçons » et « Progression » montrent les mêmes formations d’un élève :
/// elles partagent un modèle par formation au lieu de tout relire chacune.
@MainActor enum SchoolTrainingModelCache {
    private static var models: [UUID: SchoolTrainingWorkspace] = [:]

    /// Fermeture du compte ou relecture complète : aucune leçon ni progression ne reste en mémoire
    /// pour le compte suivant, même si aucun écran ne les affiche plus.
    static func reset() {
        for model in models.values { model.invalidate() }
        models = [:]
    }

    static func model(scope: SchoolCommandScope, membership: SchoolMembership, learnerID: UUID, trainingID: UUID,
                      client: SchoolTrainingClient) -> (model: SchoolTrainingWorkspace, isNew: Bool) {
        if let current = models[trainingID], current.scope == scope, current.membership == membership, current.learnerID == learnerID,
           current.client.baseURL == client.baseURL, !current.accessRevoked, !current.invalidated {
            return (current, false)
        }
        // Un autre compte, d’autres droits ou un autre élève : les modèles gardés ne servent plus.
        // Un écran encore ouvert garde son propre modèle : il n’est pas invalidé ici.
        models = models.filter { $0.value.scope == scope && $0.value.membership == membership && $0.value.learnerID == learnerID }
        let value = SchoolTrainingWorkspace(scope: scope, membership: membership, learnerID: learnerID, trainingID: trainingID, client: client)
        models[trainingID] = value
        return (value, true)
    }
}
