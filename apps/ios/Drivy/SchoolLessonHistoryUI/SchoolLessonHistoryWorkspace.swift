import Foundation
import Observation

/// Whose lessons the history reads. The server checks the filter again; « Toute l’école »
/// only returns what this account may read.
enum SchoolLessonHistoryScope: String, Hashable, Sendable {
    case mine, school
}

/// « Afficher » : narrows the lessons already read. It never widens access.
enum SchoolLessonHistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, withReport, toFinish, closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Toutes"
        case .withReport: "Avec bilan"
        case .toFinish: "À terminer"
        case .closed: "Annulées et absences"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "Aucune leçon passée"
        case .withReport: "Aucune leçon avec bilan"
        case .toFinish: "Aucune leçon à terminer"
        case .closed: "Aucune leçon annulée ni absence"
        }
    }

    /// « Avec bilan » follows the word the row shows (a shared report), so the filter and the list agree.
    func includes(_ lesson: SchoolLesson, now: Date = Date()) -> Bool {
        switch self {
        case .all: true
        case .withReport: lesson.drivyContents.contains(.report)
        case .toFinish: lesson.drivyState(now: now) == .toFinish
        case .closed: lesson.status == "CANCELLED" || lesson.status == "NO_SHOW"
        }
    }
}

struct SchoolLessonHistoryMonth: Identifiable, Equatable {
    let id: String
    let title: String
    let lessons: [SchoolLesson]
}

/// Past lessons and lessons left to finish for one school scope, page after page in the order
/// the server sorted them. Every page of one reading shares the same « before » instant: the
/// cursor is bound to it, and a lesson that starts meanwhile cannot shift the pages.
@MainActor @Observable final class SchoolLessonHistoryWorkspace: Identifiable {
    typealias PageReader = @MainActor (_ before: Date, _ instructorMembershipID: UUID?, _ newestFirst: Bool,
                                       _ cursor: String?) async throws -> SchoolPage<SchoolLesson>

    static let maximumLessons = 10_000

    let id = UUID()
    let scope: SchoolCommandScope
    private(set) var reach: SchoolLessonHistoryScope
    private(set) var newestFirst = true
    private(set) var lessons: [SchoolLesson] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isLoadingAll = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var moreErrorMessage: String?
    private(set) var accessRevoked = false
    private(set) var loadedAt: Date?
    @ObservationIgnored private let readPage: PageReader
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var before = Date()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var seenCursors: Set<String> = []
    @ObservationIgnored private var moreTask: Task<Void, Never>?
    @ObservationIgnored private var allRun: UUID?
    @ObservationIgnored private var wantsAll = false
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, reach: SchoolLessonHistoryScope, readPage: @escaping PageReader,
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.scope = scope; self.reach = reach; self.readPage = readPage; self.now = now
    }

    convenience init(scope: SchoolCommandScope, client: SchoolAgendaClient, reach: SchoolLessonHistoryScope) {
        let schoolID = scope.schoolID
        self.init(scope: scope, reach: reach, readPage: { before, instructorMembershipID, newestFirst, cursor in
            try await client.lessonHistory(schoolID: schoolID, before: before, instructorMembershipID: instructorMembershipID,
                newestFirst: newestFirst, cursor: cursor)
        })
    }

    /// Every lesson this account may read has been read: only then can « aucun résultat » be said.
    var isComplete: Bool { hasLoaded && nextCursor == nil && !accessRevoked }
    private var instructorFilter: UUID? { reach == .mine ? scope.membershipID : nil }

    // MARK: Reading

    /// `keepingCurrent` : silent reading. What is shown stays until the answer, and as many
    /// lessons as were shown are read again before the swap, so the list does not shrink under the reader.
    func load(keepingCurrent: Bool = false) async {
        guard !invalidated else { return }
        let request = UUID(); generation = request
        moreTask?.cancel(); moreTask = nil
        let keeps = keepingCurrent && hasLoaded && !accessRevoked
        let target = wantsAll ? Self.maximumLessons : lessons.count
        isLoadingMore = false; moreErrorMessage = nil
        if !keeps {
            lessons = []; nextCursor = nil; seenCursors = []; hasLoaded = false; errorMessage = nil
            isLoading = true
        }
        defer { if current(request) { isLoading = false } }
        let anchor = now()
        do {
            var fresh: [SchoolLesson] = []
            var cursor: String?
            var seen: Set<String> = []
            repeat {
                let page = try await readPage(anchor, instructorFilter, newestFirst, cursor)
                guard current(request) else { return }
                try Self.checkProgress(from: cursor, to: page.nextCursor, seen: seen)
                if let cursor { seen.insert(cursor) }
                fresh = Self.merging(fresh, page.items)
                cursor = page.nextCursor
                guard fresh.count <= Self.maximumLessons else { throw SchoolAgendaFailure.invalidResponse }
            } while cursor != nil && keeps && fresh.count < target
            lessons = fresh; nextCursor = cursor; seenCursors = seen; before = anchor
            hasLoaded = true; loadedAt = now(); accessRevoked = false; errorMessage = nil
        } catch {
            guard current(request) else { return }
            if Self.isCancellation(error) { return }
            fail(error)
            return
        }
        isLoading = false
        if wantsAll { await loadAll() }
    }

    /// Next page. A second caller (the end of the list and a search reading everything) waits for the same request.
    func loadMore() async {
        if let moreTask { await moreTask.value; return }
        guard !invalidated, !accessRevoked, !isLoading, hasLoaded, let cursor = nextCursor else { return }
        let request = generation
        isLoadingMore = true; moreErrorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchMore(cursor: cursor, request: request)
        }
        moreTask = task
        await task.value
        if moreTask == task { moreTask = nil; isLoadingMore = false }
    }

    private func fetchMore(cursor: String, request: UUID) async {
        do {
            let page = try await readPage(before, instructorFilter, newestFirst, cursor)
            guard current(request), nextCursor == cursor else { return }
            try Self.checkProgress(from: cursor, to: page.nextCursor, seen: seenCursors)
            seenCursors.insert(cursor)
            lessons = Self.merging(lessons, page.items)
            nextCursor = page.nextCursor
        } catch {
            guard current(request) else { return }
            if Self.revokesAccess(error) { fail(error) }
            else if !Self.isCancellation(error) { moreErrorMessage = Self.message(error) }
        }
    }

    /// A search or a filter applies to the whole history, never to the pages read so far.
    func setFullHistory(_ wanted: Bool) async {
        wantsAll = wanted
        if wanted { await loadAll() }
    }

    func loadAll() async {
        guard !invalidated, !accessRevoked, hasLoaded, !isLoading, allRun != generation else { return }
        let request = generation
        allRun = request; isLoadingAll = true
        defer { if allRun == request { allRun = nil; isLoadingAll = false } }
        while let cursor = nextCursor, current(request), wantsAll, moreErrorMessage == nil, !Task.isCancelled {
            guard lessons.count < Self.maximumLessons else {
                moreErrorMessage = "L’historique est trop long pour être lu en une fois. Affine avec « Mes leçons » ou réessaie."
                return
            }
            await loadMore()
            // A page that neither advances nor fails would loop forever: stop instead.
            if nextCursor == cursor && moreErrorMessage == nil { return }
        }
    }

    /// « Réessayer » under the list: the failed page, then the rest when everything is wanted.
    func retryMore() async {
        await loadMore()
        if wantsAll { await loadAll() }
    }

    func show(_ reach: SchoolLessonHistoryScope) async {
        guard reach != self.reach else { return }
        self.reach = reach
        await load()
    }

    /// The server sorts. A history already read to its end is the same list reversed, without a request.
    func sort(newestFirst: Bool) async {
        guard newestFirst != self.newestFirst else { return }
        self.newestFirst = newestFirst
        if isComplete && !isLoading && errorMessage == nil {
            lessons.reverse()
            return
        }
        await load()
    }

    func invalidate() {
        invalidated = true; generation = UUID()
        moreTask?.cancel(); moreTask = nil; allRun = nil
        lessons = []; nextCursor = nil; seenCursors = []
        isLoading = false; isLoadingMore = false; isLoadingAll = false
        errorMessage = nil; moreErrorMessage = nil
    }

    // MARK: Presentation

    func visible(filter: SchoolLessonHistoryFilter, search: String, now: Date = Date()) -> [SchoolLesson] {
        Self.visible(lessons, filter: filter, search: search, now: now)
    }

    static func needsFullHistory(filter: SchoolLessonHistoryFilter, search: String) -> Bool {
        filter != .all || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func visible(_ lessons: [SchoolLesson], filter: SchoolLessonHistoryFilter, search: String, now: Date = Date()) -> [SchoolLesson] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        guard filter != .all || !words.isEmpty else { return lessons }
        return lessons.filter { filter.includes($0, now: now) && matches($0, words: words) }
    }

    /// Every word typed must be in the learner’s name, whatever the case or the accents.
    static func matches(_ lesson: SchoolLesson, words: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        guard let name = lesson.providedLearnerName else { return false }
        let locale = Locale(identifier: "fr_CH")
        return words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil }
    }

    /// Months in the order of the list, each in the time zone of its lessons.
    static func months(_ lessons: [SchoolLesson]) -> [SchoolLessonHistoryMonth] {
        var order: [String] = []
        var grouped: [String: (title: String, lessons: [SchoolLesson])] = [:]
        for lesson in lessons {
            let key = SchoolTrainingFormatting.monthKey(lesson.plannedStart, zone: lesson.timeZone)
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = (SchoolTrainingFormatting.monthTitle(lesson.plannedStart, zone: lesson.timeZone), [])
            }
            grouped[key]?.lessons.append(lesson)
        }
        return order.compactMap { key in grouped[key].map { SchoolLessonHistoryMonth(id: key, title: $0.title, lessons: $0.lessons) } }
    }

    /// The instructor is named only when the reader is someone else (whole school).
    func instructorName(_ lesson: SchoolLesson) -> String? {
        guard reach == .school, lesson.instructorMembershipId != scope.membershipID else { return nil }
        return lesson.providedInstructorName
    }

    /// A lesson read twice keeps its latest version and its first place.
    static func merging(_ current: [SchoolLesson], _ page: [SchoolLesson]) -> [SchoolLesson] {
        var result = current
        var places: [UUID: Int] = [:]
        for (index, lesson) in current.enumerated() { places[lesson.id] = index }
        for lesson in page {
            if let index = places[lesson.id] {
                if lesson.version >= result[index].version { result[index] = lesson }
            } else {
                places[lesson.id] = result.count
                result.append(lesson)
            }
        }
        return result
    }

    /// A cursor that comes back, now or later, would read the same pages without end.
    nonisolated static func checkProgress(from cursor: String?, to next: String?, seen: Set<String>) throws {
        guard let next else { return }
        guard next != cursor, !seen.contains(next) else { throw SchoolAgendaFailure.invalidResponse }
    }

    // MARK: Failures

    static func revokesAccess(_ error: Error) -> Bool {
        switch error as? SchoolAgendaFailure {
        case .authentication, .forbidden: true
        default: false
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
    }

    private static func message(_ error: Error) -> String {
        switch error as? SchoolAgendaFailure {
        case .authentication: "Reconnecte-toi pour retrouver tes leçons."
        case .forbidden: "Tes accès ont changé. Actualise ton école."
        case .unavailable: "Connexion impossible. Vérifie le réseau puis réessaie."
        default: "Les leçons n’ont pas pu être chargées. Réessaie."
        }
    }

    private func fail(_ error: Error) {
        if Self.revokesAccess(error) {
            accessRevoked = true; lessons = []; nextCursor = nil; seenCursors = []
        }
        errorMessage = Self.message(error)
    }

    private func current(_ request: UUID) -> Bool { !invalidated && generation == request }
}
