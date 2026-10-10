import Foundation
import Observation

/// In-memory, authorized projections. Changing account or school drops all
/// school data synchronously; a late response never restores the old context.
@MainActor
@Observable
final class SchoolWorkspace {
    private(set) var person: SchoolPerson?
    private(set) var membership: SchoolMembership?
    private(set) var school: SchoolDetails?
    private(set) var learners: [SchoolLearner] = []
    private(set) var learner: SchoolLearner?
    private(set) var trainings: [SchoolTraining] = []
    private(set) var training: SchoolTraining?
    private(set) var selectedLearnerID: UUID?
    private(set) var selectedTrainingID: UUID?
    private(set) var searchText = ""
    private(set) var nextLearnersCursor: String?
    private(set) var nextTrainingsCursor: String?

    private(set) var isLoadingAccount = false
    private(set) var isLoadingSchool = false
    private(set) var isSearching = false
    private(set) var isLoadingMoreLearners = false
    private(set) var isLoadingLearner = false
    private(set) var isLoadingTrainings = false
    private(set) var isLoadingMoreTrainings = false
    private(set) var isLoadingTraining = false
    private(set) var requiresAuthentication = false
    /// Signed in, but the identity belongs to no school yet: joining with a code is the way in.
    private(set) var identityNotLinked = false
    /// The school refused this account (session expired, access withdrawn, identity not linked).
    /// A network failure never sets it: an ongoing trip keeps recording.
    private(set) var accessRevoked = false

    private(set) var accountError: String?
    private(set) var schoolError: String?
    private(set) var learnersError: String?
    private(set) var learnerError: String?
    private(set) var trainingsError: String?
    private(set) var trainingError: String?

    @ObservationIgnored private let api: any SchoolAPI
    @ObservationIgnored private var accountRequest = UUID()
    @ObservationIgnored private var accountRefresh = UUID()
    @ObservationIgnored private var schoolScope = UUID()
    @ObservationIgnored private var searchRequest = UUID()
    @ObservationIgnored private var learnerRequest = UUID()
    @ObservationIgnored private var trainingsRequest = UUID()
    @ObservationIgnored private var trainingRequest = UUID()
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var learnerCursors: Set<String> = []
    @ObservationIgnored private var trainingCursors: Set<String> = []
    @ObservationIgnored private var accountReadAt: Date?

    init(api: any SchoolAPI) { self.api = api }

    var isLearnerOnly: Bool {
        guard let roles = membership?.roles else { return false }
        return roles.contains("LEARNER") && !roles.contains("ADMIN") && !roles.contains("INSTRUCTOR")
    }

    func reset() {
        SchoolTrainingModelCache.reset()
        accountRequest = UUID()
        accountRefresh = UUID()
        person = nil
        accountError = nil
        requiresAuthentication = false
        identityNotLinked = false
        accessRevoked = false
        accountReadAt = nil
        isLoadingAccount = false
        clearSchool()
    }

    /// Lecture du compte. Quand un compte est déjà chargé et n’a pas été refusé, la relecture est silencieuse :
    /// rien n’est effacé à l’écran (une feuille ouverte, un dossier, un trajet en cours restent en place) et seul un
    /// changement de droits recharge l’école. Sinon (première lecture, accès refusé, déconnexion), tout repart de zéro.
    func loadAccount() async {
        if person != nil, !accessRevoked, !isLoadingAccount {
            await refreshAccount(minimumInterval: 0)
            return
        }
        await loadAccountFromScratch()
    }

    private func loadAccountFromScratch() async {
        let preferredSchool = membership?.schoolId
        reset()
        let request = accountRequest
        isLoadingAccount = true
        do {
            let result = try await api.me()
            guard request == accountRequest else { return }
            person = result
            accountReadAt = Date()
            isLoadingAccount = false
            if let preferred = result.memberships.first(where: { $0.schoolId == preferredSchool }) {
                await selectSchool(preferred)
            } else if result.memberships.count == 1, let only = result.memberships.first {
                await selectSchool(only)
            }
        } catch {
            guard request == accountRequest else { return }
            isLoadingAccount = false
            if !invalidateAccess(for: error) { accountError = message(for: error) }
        }
    }

    /// Return to the app: re-read the account without clearing anything on screen, at most
    /// every five minutes. Only a change of rights in the current school reloads it; a network
    /// failure changes nothing, a refusal from the school closes the account as any read does.
    func refreshAccount(minimumInterval: TimeInterval = 300, now: Date = Date()) async {
        guard let current = person, !isLoadingAccount else { return }
        if let accountReadAt, now.timeIntervalSince(accountReadAt) < minimumInterval { return }
        let request = accountRequest
        let previousReadAt = accountReadAt
        accountRefresh = UUID()
        let refresh = accountRefresh
        accountReadAt = now
        do {
            let result = try await api.me()
            // Several screens can request a silent refresh at once. Only the latest
            // reading may replace the account and its rights, even within one session.
            guard request == accountRequest, refresh == accountRefresh else { return }
            guard result.personId == current.personId else { await loadAccountFromScratch(); return }
            person = result
            guard let selected = membership else {
                if result.memberships.count == 1, let only = result.memberships.first { await selectSchool(only) }
                return
            }
            guard let updated = result.memberships.first(where: { $0.schoolId == selected.schoolId }) else {
                // No longer a member of this school.
                clearSchool()
                if result.memberships.count == 1, let only = result.memberships.first { await selectSchool(only) }
                return
            }
            if updated.membershipId != selected.membershipId || updated.accessEpoch != selected.accessEpoch
                || Set(updated.roles) != Set(selected.roles) || Set(updated.grants) != Set(selected.grants) {
                await selectSchool(updated)
            } else if updated != selected {
                // Same rights (a renamed school): the projection changes, nothing is reloaded.
                membership = updated
            }
        } catch {
            guard request == accountRequest, refresh == accountRefresh else { return }
            // Une panne passagère ne compte pas comme une lecture : la prochaine occasion réessaie.
            if !invalidateAccess(for: error) { accountReadAt = previousReadAt }
        }
    }

    func selectSchool(_ selected: SchoolMembership) async {
        guard person?.memberships.contains(selected) == true else { return }
        var resumesLearner = false
        if membership == selected {
            // Même école, mêmes droits (nouvel essai, retour d'une adhésion) : la portée reste en place pour que les
            // écrans ouverts ne se ferment pas. Les réponses en vol de l'ancienne lecture sont écartées par le nouveau scope.
            schoolScope = UUID()
            schoolError = nil
            isLoadingSchool = false
            // Une lecture du dossier écartée ici ne rend jamais la main : ses indicateurs repartent de zéro et le
            // dossier est relu une fois l'école confirmée, au lieu de rester sur un chargement sans fin.
            resumesLearner = selectedLearnerID != nil
                && (isLoadingLearner || isLoadingTrainings || isLoadingMoreTrainings || (learner == nil && learnerError == nil))
            isLoadingLearner = false; isLoadingTrainings = false; isLoadingMoreTrainings = false
            // Même règle pour la liste : une recherche ou une page écartée ne laisse pas son attente affichée.
            isSearching = false; isLoadingMoreLearners = false
        } else {
            clearSchool()
            membership = selected
        }
        let scope = schoolScope
        isLoadingSchool = true
        do {
            let result = try await api.school(id: selected.schoolId)
            guard scope == schoolScope else { return }
            guard result.id == selected.schoolId else { throw SchoolAPIError.invalidResponse }
            school = result
            isLoadingSchool = false
            if result.status == "ACTIVE" { await searchLearners("") }
            if resumesLearner, scope == schoolScope, selectedLearnerID != nil, !isLoadingLearner {
                await loadSelectedLearner()
            }
        } catch {
            guard scope == schoolScope else { return }
            isLoadingSchool = false
            if !invalidateAccess(for: error) { schoolError = message(for: error) }
        }
    }

    func leaveSchool() { clearSchool() }

    func rejectCurrentAccess(requiresAuthentication: Bool) {
        invalidateAccess(for: requiresAuthentication ? SchoolAPIError.unauthorized : SchoolAPIError.forbidden)
    }

    /// Called by the search field. Purge happens at keystroke time, before the
    /// debounce delay or any transport cancellation can complete.
    func setSearchText(_ text: String) {
        beginSearch(text)
        guard let schoolID = membership?.schoolId else { return }
        let scope = schoolScope
        let request = searchRequest
        let query = normalizedQuery
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.fetchLearners(schoolID: schoolID, query: query, scope: scope, request: request)
        }
    }

    /// Immediate equivalent used for explicit retry and deterministic tests.
    func searchLearners(_ text: String) async {
        let sameQuery = text.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedQuery
        beginSearch(text, preservingSelection: sameQuery)
        guard let schoolID = membership?.schoolId else { return }
        await fetchLearners(schoolID: schoolID, query: normalizedQuery, scope: schoolScope, request: searchRequest)
    }

    func loadMoreLearners() async {
        guard !isSearching, !isLoadingMoreLearners,
              let schoolID = membership?.schoolId, let cursor = nextLearnersCursor else { return }
        let scope = schoolScope
        let request = searchRequest
        let query = normalizedQuery
        isLoadingMoreLearners = true
        learnersError = nil
        do {
            let page = try await api.learners(schoolID: schoolID, query: query, cursor: cursor)
            guard scope == schoolScope, request == searchRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID }) else { throw SchoolAPIError.invalidResponse }
            guard page.nextCursor != cursor,
                  page.nextCursor.map({ !learnerCursors.contains($0) }) ?? true else { throw SchoolAPIError.invalidCursor }
            learnerCursors.insert(cursor)
            Self.merge(page.items, into: &learners)
            nextLearnersCursor = page.nextCursor
            isLoadingMoreLearners = false
        } catch {
            guard scope == schoolScope, request == searchRequest else { return }
            isLoadingMoreLearners = false
            if !invalidateAccess(for: error) { learnersError = message(for: error) }
        }
    }

    /// Nom d’un élève hors de la page affichée (trajet en cours) ; une lecture refusée ou en panne ne dit rien.
    func learnerName(_ id: UUID) async -> String? {
        guard let schoolID = membership?.schoolId else { return nil }
        let learner = try? await api.learner(schoolID: schoolID, id: id)
        return learner?.schoolId == schoolID && learner?.id == id ? learner?.displayName : nil
    }

    func selectLearner(_ id: UUID?) {
        guard selectedLearnerID != id else { return }
        clearLearner()
        selectedLearnerID = id
    }

    func loadSelectedLearner() async {
        guard let schoolID = membership?.schoolId, let id = selectedLearnerID else { return }
        let scope = schoolScope
        learnerRequest = UUID()
        let request = learnerRequest
        trainingsRequest = UUID()
        isLoadingTrainings = false
        isLoadingMoreTrainings = false
        learnerError = nil
        // Relecture du dossier déjà affiché : il reste à l’écran jusqu’à la réponse, sans écran de chargement.
        isLoadingLearner = learner?.id != id
        do {
            let result = try await api.learner(schoolID: schoolID, id: id)
            guard scope == schoolScope, request == learnerRequest, selectedLearnerID == id else { return }
            guard result.id == id, result.schoolId == schoolID else { throw SchoolAPIError.invalidResponse }
            learner = result
            // La liste Élèves porte le même élève : sa ligne suit le dossier relu (nom, coordonnées) sans attendre sa
            // propre relecture. Ni l’ordre ni la pagination ne changent, et un élève absent de la liste n’y est pas ajouté.
            if let row = learners.firstIndex(where: { $0.id == result.id }) { learners[row] = result }
            isLoadingLearner = false
            await loadTrainings()
        } catch {
            guard scope == schoolScope, request == learnerRequest else { return }
            isLoadingLearner = false
            if error as? SchoolAPIError == .notFound {
                clearLearner()
                selectedLearnerID = id
            }
            if !invalidateAccess(for: error) { learnerError = message(for: error) }
        }
    }

    func loadTrainings() async {
        guard let schoolID = membership?.schoolId, let learnerID = selectedLearnerID, learner != nil else { return }
        let scope = schoolScope
        let request = learnerRequest
        trainingsRequest = UUID()
        let pageRequest = trainingsRequest
        // Refreshing the list must not close a formation already open in the dossier, nor remove the
        // screen (and the sheets it carries) that depends on it: the rows already read stay until the
        // answer replaces them. They always belong to this learner (changing learner clears them).
        // Its independent detail request remains bound to its selection and schoolScope.
        trainingsError = nil
        isLoadingMoreTrainings = false
        isLoadingTrainings = true
        do {
            let page = try await api.trainings(schoolID: schoolID, learnerID: learnerID, cursor: nil)
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID && $0.learnerId == learnerID }) else { throw SchoolAPIError.invalidResponse }
            var fresh: [SchoolTraining] = []
            Self.merge(page.items, into: &fresh)
            trainings = fresh
            trainingCursors = []
            nextTrainingsCursor = page.nextCursor
            isLoadingTrainings = false
        } catch {
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            isLoadingTrainings = false
            if !invalidateAccess(for: error) { trainingsError = message(for: error) }
        }
    }

    func loadMoreTrainings() async {
        guard !isLoadingTrainings, !isLoadingMoreTrainings,
              let schoolID = membership?.schoolId, let learnerID = selectedLearnerID,
              let cursor = nextTrainingsCursor else { return }
        let scope = schoolScope
        let request = learnerRequest
        let pageRequest = trainingsRequest
        isLoadingMoreTrainings = true
        trainingsError = nil
        do {
            let page = try await api.trainings(schoolID: schoolID, learnerID: learnerID, cursor: cursor)
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID && $0.learnerId == learnerID }) else { throw SchoolAPIError.invalidResponse }
            guard page.nextCursor != cursor,
                  page.nextCursor.map({ !trainingCursors.contains($0) }) ?? true else { throw SchoolAPIError.invalidCursor }
            trainingCursors.insert(cursor)
            Self.merge(page.items, into: &trainings)
            nextTrainingsCursor = page.nextCursor
            isLoadingMoreTrainings = false
        } catch {
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            isLoadingMoreTrainings = false
            if !invalidateAccess(for: error) { trainingsError = message(for: error) }
        }
    }

    /// Les filtres par permis portent sur toutes les formations de l’élève, pas sur la première page.
    /// Une panne laisse le curseur en place : le dossier propose alors de continuer.
    func loadRemainingTrainings() async {
        while let cursor = nextTrainingsCursor, !isLoadingTrainings, !isLoadingMoreTrainings {
            await loadMoreTrainings()
            if nextTrainingsCursor == cursor || trainingsError != nil { return }
        }
    }

    func selectTraining(_ id: UUID?) {
        trainingRequest = UUID()
        training = nil
        trainingError = nil
        isLoadingTraining = false
        selectedTrainingID = id
    }

    func loadSelectedTraining() async {
        guard let schoolID = membership?.schoolId, let learnerID = selectedLearnerID,
              let id = selectedTrainingID else { return }
        let scope = schoolScope
        trainingRequest = UUID()
        let request = trainingRequest
        isLoadingTraining = true
        if training?.id != id { training = nil }
        trainingError = nil
        do {
            let result = try await api.training(schoolID: schoolID, id: id)
            guard scope == schoolScope, request == trainingRequest, id == selectedTrainingID else { return }
            guard result.id == id, result.schoolId == schoolID, result.learnerId == learnerID else { throw SchoolAPIError.invalidResponse }
            training = result
            isLoadingTraining = false
        } catch {
            guard scope == schoolScope, request == trainingRequest else { return }
            isLoadingTraining = false
            if !invalidateAccess(for: error) { trainingError = message(for: error) }
        }
    }

    private var normalizedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func beginSearch(_ text: String, preservingSelection: Bool = false) {
        debounceTask?.cancel()
        debounceTask = nil
        searchRequest = UUID()
        searchText = text
        if !preservingSelection { learners = [] }
        nextLearnersCursor = nil
        learnerCursors = []
        learnersError = nil
        isSearching = membership != nil
        isLoadingMoreLearners = false
        if !preservingSelection { clearLearner() }
    }

    private func fetchLearners(schoolID: UUID, query: String, scope: UUID, request: UUID) async {
        guard scope == schoolScope, request == searchRequest else { return }
        do {
            let page = try await api.learners(schoolID: schoolID, query: query, cursor: nil)
            guard scope == schoolScope, request == searchRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID }) else { throw SchoolAPIError.invalidResponse }
            learners = []
            Self.merge(page.items, into: &learners)
            nextLearnersCursor = page.nextCursor
            isSearching = false
        } catch {
            guard scope == schoolScope, request == searchRequest else { return }
            isSearching = false
            if !invalidateAccess(for: error) { learnersError = message(for: error) }
        }
    }

    private func clearSchool() {
        schoolScope = UUID()
        membership = nil
        school = nil
        schoolError = nil
        isLoadingSchool = false
        beginSearch("")
    }

    private func clearLearner() {
        learnerRequest = UUID()
        trainingsRequest = UUID()
        selectedLearnerID = nil
        learner = nil
        learnerError = nil
        isLoadingLearner = false
        trainings = []
        nextTrainingsCursor = nil
        trainingCursors = []
        trainingsError = nil
        isLoadingTrainings = false
        isLoadingMoreTrainings = false
        selectTraining(nil)
    }

    @discardableResult
    private func invalidateAccess(for error: any Error) -> Bool {
        guard let failure = error as? SchoolAPIError else { return false }
        switch failure {
        case .unauthorized, .forbidden, .identityNotLinked:
            reset()
            requiresAuthentication = failure == .unauthorized
            identityNotLinked = failure == .identityNotLinked
            accessRevoked = true
            accountError = message(for: failure)
            return true
        default:
            return false
        }
    }

    private func message(for error: any Error) -> String {
        if error is CancellationError { return "Le chargement a été interrompu. Réessaie." }
        return (error as? SchoolAPIError)?.localizedDescription ?? "La connexion a échoué. Tes données n’ont pas été modifiées."
    }

    private static func merge<T: Identifiable>(_ newItems: [T], into items: inout [T]) where T.ID: Hashable {
        var indices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        for item in newItems {
            if let index = indices[item.id] { items[index] = item }
            else { indices[item.id] = items.count; items.append(item) }
        }
    }
}
