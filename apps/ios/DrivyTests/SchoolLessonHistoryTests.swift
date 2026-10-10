import Foundation
import Testing
@testable import Drivy

/// Profil → Leçons : mois par fuseau, pagination décroissante, recherche sur tout l’historique, boucle de curseur.
@MainActor
struct SchoolLessonHistoryTests {
    private static let scope = SchoolCommandScope(personID: UUID(uuidString: "70000000-0000-4000-8000-000000000001")!,
        schoolID: UUID(uuidString: "70000000-0000-4000-8000-000000000002")!,
        membershipID: UUID(uuidString: "70000000-0000-4000-8000-000000000003")!, accessEpoch: 1,
        apiBaseURL: "https://api.example.invalid")
    private static let colleague = UUID(uuidString: "70000000-0000-4000-8000-000000000004")!

    private static func lesson(_ index: Int, start: String, name: String? = "Camille Perret", status: String = "COMPLETED",
                               zone: String = "Europe/Zurich", instructor: UUID? = nil, version: Int = 1,
                               revision: UUID? = nil, actualStart: String? = nil) -> SchoolLesson {
        let end = ISO8601DateFormatter().string(from: (SchoolLesson.date(start) ?? Date(timeIntervalSince1970: 0)).addingTimeInterval(3_000))
        return SchoolLesson(id: UUID(uuidString: String(format: "71000000-0000-4000-8000-%012d", index))!, schoolId: scope.schoolID,
            version: version, trainingId: UUID(uuidString: "70000000-0000-4000-8000-000000000005")!,
            learnerId: UUID(uuidString: String(format: "72000000-0000-4000-8000-%012d", index))!,
            instructorMembershipId: instructor ?? scope.membershipID, plannedStart: start, plannedEnd: end, timeZone: zone,
            meetingPoint: "Gare", status: status, priceCentsSnapshot: 9_000, bufferMinutesSnapshot: 10,
            actualStart: actualStart, actualEnd: nil, permitWarning: false, publicationVersion: 0, currentPublishedRevisionId: revision,
            commercialRevisionVersion: 1, learnerDisplayName: name, instructorDisplayName: "Luc Exemple")
    }

    private static func model(_ pages: HistoryPages, reach: SchoolLessonHistoryScope = .mine) -> SchoolLessonHistoryWorkspace {
        SchoolLessonHistoryWorkspace(scope: scope, reach: reach, readPage: { before, instructor, newestFirst, cursor in
            try pages.read(before: before, instructor: instructor, newestFirst: newestFirst, cursor: cursor)
        })
    }

    @Test func monthsFollowTheTimeZoneOfTheLesson() {
        // 22:30 UTC le 30 septembre : déjà le 1er octobre à Zurich, encore le 30 septembre à New York.
        let zurich = Self.lesson(1, start: "2026-09-30T22:30:00Z")
        let evening = Self.lesson(2, start: "2026-09-30T21:00:00Z")
        let newYork = Self.lesson(3, start: "2026-09-30T22:30:00Z", zone: "America/New_York")
        let months = SchoolLessonHistoryWorkspace.months([zurich, evening])
        #expect(months.map(\.id) == ["2026-10", "2026-9"])
        #expect(months[0].title.hasPrefix("Octobre") && months[0].title.hasSuffix("2026"))
        #expect(months[1].title.hasPrefix("Septembre") && months[1].lessons == [evening])
        #expect(SchoolLessonHistoryWorkspace.months([newYork]).map(\.id) == ["2026-9"])
        // L’ordre de la liste est gardé : anciennes d’abord, septembre passe devant octobre.
        #expect(SchoolLessonHistoryWorkspace.months([evening, zurich]).map(\.id) == ["2026-9", "2026-10"])
        #expect(SchoolLessonHistoryWorkspace.months([]).isEmpty)
    }

    @Test func pagesAreReadNewestFirstWithOneAnchorAndTheReadersOwnLessons() async throws {
        let first = [Self.lesson(1, start: "2026-10-05T08:00:00Z"), Self.lesson(2, start: "2026-10-04T08:00:00Z")]
        let second = [Self.lesson(3, start: "2026-09-20T08:00:00Z")]
        let pages = HistoryPages([.success(.init(items: first, nextCursor: "page-2")), .success(.init(items: second, nextCursor: nil))])
        let model = Self.model(pages)
        await model.load()
        try #require(model.hasLoaded && model.errorMessage == nil)
        #expect(model.lessons == first && model.nextCursor == "page-2" && !model.isComplete)
        await model.loadMore()
        #expect(model.lessons == first + second && model.isComplete && !model.isLoadingMore && model.moreErrorMessage == nil)
        try #require(pages.calls.count == 2)
        #expect(pages.calls[0].cursor == nil && pages.calls[1].cursor == "page-2")
        #expect(pages.calls.allSatisfy { $0.newestFirst && $0.instructor == Self.scope.membershipID })
        // Le curseur est lié à `to` : toutes les pages d’une lecture partent du même instant.
        #expect(pages.calls[0].before == pages.calls[1].before)
        // Rien à lire de plus : aucune requête.
        await model.loadMore()
        #expect(pages.calls.count == 2)
    }

    @Test func theWholeSchoolIsReadWithoutAnInstructorFilterAndNamesTheOtherInstructors() async throws {
        let mine = Self.lesson(1, start: "2026-10-05T08:00:00Z")
        let other = Self.lesson(2, start: "2026-10-04T08:00:00Z", instructor: Self.colleague)
        let pages = HistoryPages([.success(.init(items: [mine], nextCursor: nil)), .success(.init(items: [mine, other], nextCursor: nil))])
        let model = Self.model(pages)
        await model.load()
        #expect(model.instructorName(mine) == nil)
        await model.show(.school)
        try #require(pages.calls.count == 2)
        #expect(pages.calls[1].instructor == nil && model.lessons == [mine, other])
        #expect(model.instructorName(other) == "Luc Exemple" && model.instructorName(mine) == nil)
        await model.show(.school)
        #expect(pages.calls.count == 2)
    }

    @Test func aSearchReadsTheWholeHistoryBeforeAnythingIsCalledEmpty() async throws {
        let pages = HistoryPages([
            .success(.init(items: [Self.lesson(1, start: "2026-10-05T08:00:00Z")], nextCursor: "page-2")),
            .success(.init(items: [Self.lesson(2, start: "2026-09-05T08:00:00Z", name: "Noé Exemple")], nextCursor: "page-3")),
            .success(.init(items: [Self.lesson(3, start: "2026-08-05T08:00:00Z", name: "Zoé Martin")], nextCursor: nil))
        ])
        let model = Self.model(pages)
        await model.load()
        // Sur la première page, « Zoé » est introuvable, mais l’historique n’est pas lu : rien ne peut être affirmé.
        #expect(model.visible(filter: .all, search: "zoe").isEmpty && !model.isComplete)
        #expect(SchoolLessonHistoryWorkspace.needsFullHistory(filter: .all, search: "zoe"))
        #expect(!SchoolLessonHistoryWorkspace.needsFullHistory(filter: .all, search: "  "))
        #expect(SchoolLessonHistoryWorkspace.needsFullHistory(filter: .closed, search: ""))
        await model.setFullHistory(true)
        #expect(model.isComplete && model.lessons.count == 3 && !model.isLoadingAll && pages.calls.count == 3)
        #expect(pages.calls.map(\.cursor) == [nil, "page-2", "page-3"])
        // Casse et accents ignorés ; chaque mot doit se trouver dans le nom.
        #expect(model.visible(filter: .all, search: "zoe").map(\.providedLearnerName) == ["Zoé Martin"])
        #expect(model.visible(filter: .all, search: "MARTIN zoé").count == 1)
        #expect(model.visible(filter: .all, search: "exemple").map(\.providedLearnerName) == ["Noé Exemple"])
        #expect(model.visible(filter: .all, search: "zoé perret").isEmpty)
        #expect(model.visible(filter: .all, search: " ").count == 3)
    }

    @Test func aCursorThatComesBackStopsTheReadingInsteadOfLooping() async throws {
        // Le même curseur rendu tout de suite.
        let same = HistoryPages([
            .success(.init(items: [Self.lesson(1, start: "2026-10-05T08:00:00Z")], nextCursor: "a")),
            .success(.init(items: [Self.lesson(2, start: "2026-10-04T08:00:00Z")], nextCursor: "a"))
        ])
        let stuck = Self.model(same)
        await stuck.load()
        await stuck.setFullHistory(true)
        #expect(same.calls.count == 2 && stuck.lessons.count == 1 && stuck.moreErrorMessage != nil)
        #expect(!stuck.isComplete && !stuck.isLoadingMore && !stuck.isLoadingAll && !stuck.accessRevoked)

        // Un curseur déjà parcouru, deux pages plus loin.
        let cycle = HistoryPages([
            .success(.init(items: [Self.lesson(1, start: "2026-10-05T08:00:00Z")], nextCursor: "a")),
            .success(.init(items: [Self.lesson(2, start: "2026-10-04T08:00:00Z")], nextCursor: "b")),
            .success(.init(items: [Self.lesson(3, start: "2026-10-03T08:00:00Z")], nextCursor: "a"))
        ])
        let looping = Self.model(cycle)
        await looping.load()
        await looping.setFullHistory(true)
        #expect(cycle.calls.count == 3 && looping.lessons.count == 2 && looping.moreErrorMessage != nil && !looping.isComplete)
        #expect(throws: SchoolAgendaFailure.self) {
            try SchoolLessonHistoryWorkspace.checkProgress(from: "b", to: "a", seen: ["a"])
        }
    }

    @Test func aSilentReadingKeepsTheListAndAChangedAccessClearsIt() async throws {
        let shown = [Self.lesson(1, start: "2026-10-05T08:00:00Z"), Self.lesson(2, start: "2026-10-04T08:00:00Z")]
        let newer = Self.lesson(1, start: "2026-10-05T08:00:00Z", version: 2, revision: UUID())
        let pages = HistoryPages([
            .success(.init(items: [shown[0]], nextCursor: "page-2")), .success(.init(items: [shown[1]], nextCursor: nil)),
            .failure(.unavailable),
            .success(.init(items: [newer], nextCursor: "page-2b")), .success(.init(items: [shown[1]], nextCursor: nil)),
            .failure(.forbidden)
        ])
        let model = Self.model(pages)
        await model.load()
        await model.loadMore()
        try #require(model.lessons == shown && model.isComplete)
        // Réseau coupé pendant la relecture : la liste reste, l’erreur se dit.
        await model.load(keepingCurrent: true)
        #expect(model.lessons == shown && model.errorMessage != nil && !model.accessRevoked && !model.isLoading)
        // Relecture réussie : autant de leçons qu’affichées sont relues avant l’échange, la leçon modifiée est à jour.
        await model.load(keepingCurrent: true)
        #expect(model.lessons == [newer, shown[1]] && model.errorMessage == nil && model.isComplete)
        #expect(pages.calls.count == 5 && pages.calls[4].cursor == "page-2b")
        // Accès retiré : plus rien n’est montré.
        await model.load(keepingCurrent: true)
        #expect(model.accessRevoked && model.lessons.isEmpty && model.nextCursor == nil && model.errorMessage != nil)
    }

    @Test func aCompleteHistoryIsReversedWithoutARequestAndAPartialOneIsReadAgain() async throws {
        let all = [Self.lesson(1, start: "2026-10-05T08:00:00Z"), Self.lesson(2, start: "2026-10-04T08:00:00Z")]
        let complete = HistoryPages([.success(.init(items: all, nextCursor: nil))])
        let whole = Self.model(complete)
        await whole.load()
        await whole.sort(newestFirst: false)
        #expect(whole.lessons == Array(all.reversed()) && !whole.newestFirst && complete.calls.count == 1)

        let partial = HistoryPages([.success(.init(items: [all[0]], nextCursor: "page-2")),
                                    .success(.init(items: [all[1]], nextCursor: "old-2"))])
        let part = Self.model(partial)
        await part.load()
        await part.sort(newestFirst: false)
        try #require(partial.calls.count == 2)
        // Un autre sens est une autre lecture : pas de curseur repris de l’ancien.
        #expect(partial.calls[1].cursor == nil && !partial.calls[1].newestFirst && part.lessons == [all[1]] && part.nextCursor == "old-2")
    }

    @Test func theFiltersNarrowWhatWasReadAndALessonSeenTwiceKeepsItsLatestVersion() throws {
        let now = try #require(SchoolLesson.date("2026-10-06T10:00:00Z"))
        let report = Self.lesson(1, start: "2026-10-05T08:00:00Z", revision: UUID())
        let bare = Self.lesson(2, start: "2026-10-04T08:00:00Z")
        let toFinish = Self.lesson(3, start: "2026-10-03T08:00:00Z", status: "PLANNED", actualStart: "2026-10-03T08:00:00Z")
        let running = Self.lesson(4, start: "2026-10-06T09:45:00Z", status: "PLANNED", actualStart: "2026-10-06T09:45:00Z")
        let cancelled = Self.lesson(5, start: "2026-10-02T08:00:00Z", status: "CANCELLED")
        let missed = Self.lesson(6, start: "2026-10-01T08:00:00Z", status: "NO_SHOW")
        let waiting = Self.lesson(7, start: "2026-10-03T08:00:00Z", status: "PLANNED")
        let all = [running, report, bare, toFinish, cancelled, missed, waiting]
        func shown(_ filter: SchoolLessonHistoryFilter) -> [SchoolLesson] {
            SchoolLessonHistoryWorkspace.visible(all, filter: filter, search: "", now: now)
        }
        #expect(shown(.all) == all)
        #expect(shown(.withReport) == [report])
        // Une leçon en cours n’est pas encore « à terminer ».
        #expect(shown(.toFinish) == [toFinish])
        #expect(shown(.closed) == [cancelled, missed])
        #expect(SchoolLessonHistoryFilter.allCases.map(\.title) == ["Toutes", "Avec bilan", "À terminer", "Annulées et absences"])

        let updated = Self.lesson(2, start: "2026-10-04T08:00:00Z", version: 3)
        let stale = Self.lesson(1, start: "2026-10-05T08:00:00Z", version: 0)
        #expect(SchoolLessonHistoryWorkspace.merging([report, bare], [updated, stale, toFinish]) == [report, updated, toFinish])
    }

    @Test func dossierFiltersKeepAnOverdueUnstartedLessonWaitingUntilItReallyStarts() throws {
        let now = try #require(SchoolLesson.date("2026-10-06T10:30:00Z"))
        let planned = Self.lesson(1, start: "2026-10-06T12:00:00Z", status: "PLANNED")
        let waiting = Self.lesson(2, start: "2026-10-06T10:00:00Z", status: "PLANNED")
        let oldWaiting = Self.lesson(3, start: "2026-10-05T10:00:00Z", status: "PLANNED")
        let running = Self.lesson(4, start: "2026-10-06T10:00:00Z", status: "PLANNED", actualStart: "2026-10-06T10:10:00Z")
        let toFinish = Self.lesson(5, start: "2026-10-05T10:00:00Z", status: "PLANNED", actualStart: "2026-10-05T10:10:00Z")
        let lessons = [planned, waiting, oldWaiting, running, toFinish]
        #expect(lessons.filter { TrainingLessonFilter.upcoming.includes($0, now: now) } == [planned, running])
        #expect(lessons.filter { TrainingLessonFilter.past.includes($0, now: now) } == [waiting, oldWaiting, toFinish])
        #expect(lessons.filter { TrainingLessonFilter.toFinish.includes($0, now: now) } == [toFinish])
        #expect(waiting.drivyState(now: now) == .waiting && oldWaiting.drivyState(now: now) == .waiting)
    }
}

/// Scripted pages: every call is recorded, then answered by the next entry.
@MainActor
private final class HistoryPages {
    struct Call: Equatable {
        let before: Date
        let instructor: UUID?
        let newestFirst: Bool
        let cursor: String?
    }

    private(set) var calls: [Call] = []
    private var script: [Result<SchoolPage<SchoolLesson>, SchoolAgendaFailure>]

    init(_ script: [Result<SchoolPage<SchoolLesson>, SchoolAgendaFailure>]) { self.script = script }

    func read(before: Date, instructor: UUID?, newestFirst: Bool, cursor: String?) throws -> SchoolPage<SchoolLesson> {
        calls.append(Call(before: before, instructor: instructor, newestFirst: newestFirst, cursor: cursor))
        guard !script.isEmpty else { throw SchoolAgendaFailure.invalidResponse }
        return try script.removeFirst().get()
    }
}
