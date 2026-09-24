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

    private(set) var accountError: String?
    private(set) var schoolError: String?
    private(set) var learnersError: String?
    private(set) var learnerError: String?
    private(set) var trainingsError: String?
    private(set) var trainingError: String?

    @ObservationIgnored private let api: any SchoolAPI
    @ObservationIgnored private var accountRequest = UUID()
    @ObservationIgnored private var schoolScope = UUID()
    @ObservationIgnored private var searchRequest = UUID()
    @ObservationIgnored private var learnerRequest = UUID()
    @ObservationIgnored private var trainingsRequest = UUID()
    @ObservationIgnored private var trainingRequest = UUID()
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var learnerCursors: Set<String> = []
    @ObservationIgnored private var trainingCursors: Set<String> = []

    init(api: any SchoolAPI) { self.api = api }

    var isLearnerOnly: Bool {
        guard let roles = membership?.roles else { return false }
        return roles.contains("LEARNER") && !roles.contains("ADMIN") && !roles.contains("INSTRUCTOR")
    }

    func reset() {
        accountRequest = UUID()
        person = nil
        accountError = nil
        requiresAuthentication = false
        isLoadingAccount = false
        clearSchool()
    }

    func loadAccount() async {
        let preferredSchool = membership?.schoolId
        reset()
        let request = accountRequest
        isLoadingAccount = true
        do {
            let result = try await api.me()
            guard request == accountRequest else { return }
            person = result
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

    func selectSchool(_ selected: SchoolMembership) async {
        guard person?.memberships.contains(selected) == true else { return }
        clearSchool()
        membership = selected
        let scope = schoolScope
        isLoadingSchool = true
        do {
            let result = try await api.school(id: selected.schoolId)
            guard scope == schoolScope else { return }
            guard result.id == selected.schoolId else { throw SchoolAPIError.invalidResponse }
            school = result
            isLoadingSchool = false
            if result.status == "ACTIVE" { await searchLearners("") }
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
        beginSearch(text)
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

    func selectLearner(_ id: UUID?) {
        clearLearner()
        selectedLearnerID = id
    }

    func loadSelectedLearner() async {
        guard let schoolID = membership?.schoolId, let id = selectedLearnerID else { return }
        let scope = schoolScope
        clearLearner()
        selectedLearnerID = id
        let request = learnerRequest
        learner = nil
        trainings = []
        nextTrainingsCursor = nil
        learnerError = nil
        trainingsError = nil
        isLoadingLearner = true
        do {
            let result = try await api.learner(schoolID: schoolID, id: id)
            guard scope == schoolScope, request == learnerRequest, selectedLearnerID == id else { return }
            guard result.id == id, result.schoolId == schoolID else { throw SchoolAPIError.invalidResponse }
            learner = result
            isLoadingLearner = false
            await loadTrainings()
        } catch {
            guard scope == schoolScope, request == learnerRequest else { return }
            isLoadingLearner = false
            if !invalidateAccess(for: error) { learnerError = message(for: error) }
        }
    }

    func loadTrainings() async {
        guard let schoolID = membership?.schoolId, let learnerID = selectedLearnerID, learner != nil else { return }
        let scope = schoolScope
        let request = learnerRequest
        trainingsRequest = UUID()
        let pageRequest = trainingsRequest
        trainingRequest = UUID()
        selectedTrainingID = nil
        training = nil
        trainings = []
        trainingCursors = []
        nextTrainingsCursor = nil
        trainingsError = nil
        trainingError = nil
        isLoadingMoreTrainings = false
        isLoadingTraining = false
        isLoadingTrainings = true
        do {
            let page = try await api.trainings(schoolID: schoolID, learnerID: learnerID, cursor: nil)
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID && $0.learnerId == learnerID }) else { throw SchoolAPIError.invalidResponse }
            Self.merge(page.items, into: &trainings)
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
        training = nil
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

    private func beginSearch(_ text: String) {
        debounceTask?.cancel()
        debounceTask = nil
        searchRequest = UUID()
        searchText = text
        learners = []
        nextLearnersCursor = nil
        learnerCursors = []
        learnersError = nil
        isSearching = membership != nil
        isLoadingMoreLearners = false
        clearLearner()
    }

    private func fetchLearners(schoolID: UUID, query: String, scope: UUID, request: UUID) async {
        guard scope == schoolScope, request == searchRequest else { return }
        do {
            let page = try await api.learners(schoolID: schoolID, query: query, cursor: nil)
            guard scope == schoolScope, request == searchRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID }) else { throw SchoolAPIError.invalidResponse }
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
            accountError = message(for: failure)
            return true
        default:
            return false
        }
    }

    private func message(for error: any Error) -> String {
        if error is CancellationError { return "Le chargement a été interrompu. Réessayez." }
        return (error as? SchoolAPIError)?.localizedDescription ?? "La connexion a échoué. Vos données n’ont pas été modifiées."
    }

    private static func merge<T: Identifiable>(_ newItems: [T], into items: inout [T]) where T.ID: Hashable {
        var indices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        for item in newItems {
            if let index = indices[item.id] { items[index] = item }
            else { indices[item.id] = items.count; items.append(item) }
        }
    }
}
