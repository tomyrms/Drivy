import Foundation
import Testing
@testable import Drivy

/// Grille du mois de l’agenda : même calendrier que la vue (fr_CH, lundi d’abord, fuseau de l’école).
@MainActor
struct SchoolAgendaMonthTests {
    private let calendar: Calendar = {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "fr_CH")
        result.firstWeekday = 2
        result.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return result
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Année, mois et jour dans le fuseau de l’école.
    private func parts(_ date: Date) -> [Int] {
        let value = calendar.dateComponents([.year, .month, .day], from: date)
        return [value.year ?? 0, value.month ?? 0, value.day ?? 0]
    }

    @Test func gridStartsOnMondayAndAlwaysHoldsSixWeeks() {
        // 1er octobre 2026 : un jeudi. La grille part du lundi 28 septembre.
        let days = SchoolAgendaMonth.gridDays(for: date(2026, 10, 14), calendar: calendar)
        #expect(days.count == 42)
        #expect(parts(days[0]) == [2026, 9, 28])
        #expect(parts(days[41]) == [2026, 11, 8])
        for week in stride(from: 0, to: days.count, by: 7) {
            #expect(calendar.component(.weekday, from: days[week]) == 2)
        }
        let range = SchoolAgendaMonth.gridRange(for: date(2026, 10, 14), calendar: calendar)
        #expect(range.start == days[0])
        #expect(parts(range.end) == [2026, 11, 9])
        #expect(range.contains(date(2026, 10, 1, 0)))
        #expect(range.contains(date(2026, 10, 31, 23, 59)))
    }

    @Test func monthsSpanFourFiveOrSixWeeks() {
        #expect(SchoolAgendaMonth.weeksSpanned(for: date(2021, 2, 10), calendar: calendar) == 4)
        #expect(SchoolAgendaMonth.weeksSpanned(for: date(2026, 2, 10), calendar: calendar) == 5)
        #expect(SchoolAgendaMonth.weeksSpanned(for: date(2026, 10, 10), calendar: calendar) == 5)
        // 1er mars 2026 : un dimanche, et 31 jours : six semaines, toutes dans la grille.
        #expect(SchoolAgendaMonth.weeksSpanned(for: date(2026, 3, 10), calendar: calendar) == 6)
        let march = SchoolAgendaMonth.gridDays(for: date(2026, 3, 10), calendar: calendar)
        #expect(parts(march[0]) == [2026, 2, 23])
        #expect(parts(march[41]) == [2026, 4, 5])
        #expect(march.contains { parts($0) == [2026, 3, 31] })
    }

    @Test func monthNavigationCrossesYears() {
        #expect(parts(SchoolAgendaMonth.shiftingMonth(date(2026, 12, 15), by: 1, calendar: calendar)) == [2027, 1, 15])
        #expect(parts(SchoolAgendaMonth.shiftingMonth(date(2027, 1, 10), by: -1, calendar: calendar)) == [2026, 12, 10])
        // Janvier 2027 commence un vendredi : sa grille s’ouvre sur la fin de décembre 2026.
        let january = SchoolAgendaMonth.gridDays(for: date(2027, 1, 10), calendar: calendar)
        #expect(parts(january[0]) == [2026, 12, 28])
        #expect(!SchoolAgendaMonth.isSameMonth(january[0], date(2027, 1, 10), calendar: calendar))
        #expect(SchoolAgendaMonth.isSameMonth(january[4], date(2027, 1, 10), calendar: calendar))
    }

    @Test func selectedDayIsClampedToTheShorterMonth() {
        #expect(parts(SchoolAgendaMonth.shiftingMonth(date(2026, 1, 31), by: 1, calendar: calendar)) == [2026, 2, 28])
        #expect(parts(SchoolAgendaMonth.shiftingMonth(date(2028, 1, 31), by: 1, calendar: calendar)) == [2028, 2, 29])
        #expect(parts(SchoolAgendaMonth.shiftingMonth(date(2026, 3, 31), by: -1, calendar: calendar)) == [2026, 2, 28])
        #expect(parts(SchoolAgendaMonth.shiftingMonth(date(2026, 5, 31), by: 1, calendar: calendar)) == [2026, 6, 30])
        #expect(parts(SchoolAgendaMonth.shiftingMonth(date(2026, 10, 14), by: 0, calendar: calendar)) == [2026, 10, 14])
    }

    @Test func gridDaysStayAtMidnightAcrossDaylightSavingChanges() {
        // Europe/Zurich : heure d’été le 29 mars 2026, heure d’hiver le 25 octobre 2026.
        for anchor in [date(2026, 3, 15), date(2026, 10, 15)] {
            let days = SchoolAgendaMonth.gridDays(for: anchor, calendar: calendar)
            #expect(days.count == 42)
            for (index, day) in days.enumerated() {
                let time = calendar.dateComponents([.hour, .minute], from: day)
                #expect(time.hour == 0 && time.minute == 0)
                if index > 0 {
                    #expect(calendar.dateComponents([.day], from: days[index - 1], to: day).day == 1)
                }
            }
        }
        let spring = SchoolAgendaMonth.gridDays(for: date(2026, 3, 15), calendar: calendar)
        let shortDay = spring.firstIndex { parts($0) == [2026, 3, 29] }!
        #expect(spring[shortDay + 1].timeIntervalSince(spring[shortDay]) == 23 * 3600)
        let autumn = SchoolAgendaMonth.gridDays(for: date(2026, 10, 15), calendar: calendar)
        let longDay = autumn.firstIndex { parts($0) == [2026, 10, 25] }!
        #expect(autumn[longDay + 1].timeIntervalSince(autumn[longDay]) == 25 * 3600)
        // La semaine du changement d’heure finit bien au lundi suivant à minuit.
        let week = SchoolAgendaMonth.weekRange(for: date(2026, 3, 29), calendar: calendar)
        #expect(parts(week.start) == [2026, 3, 23])
        #expect(parts(week.end) == [2026, 3, 30])
        #expect(week.end.timeIntervalSince(week.start) == 7 * 86_400 - 3600)
    }

    @Test func weekRangeIsContainedInItsMonthGrid() {
        for anchor in [date(2026, 10, 1), date(2026, 10, 31), date(2026, 3, 1), date(2027, 1, 1)] {
            let week = SchoolAgendaMonth.range(for: anchor, mode: .week, calendar: calendar)
            let month = SchoolAgendaMonth.range(for: anchor, mode: .month, calendar: calendar)
            #expect(month.contains(week))
            #expect(!week.contains(month))
        }
    }

    @Test func lessonsAreCountedOnTheirDayInTheSchoolTimeZone() {
        struct Item { let start: Date?; let order: Int }
        let iso = ISO8601DateFormatter()
        let items = [
            // 00:30 le 14 octobre à Zurich, encore le 13 en UTC.
            Item(start: iso.date(from: "2026-10-13T22:30:00Z"), order: 2),
            // 23:30 le 13 octobre à Zurich.
            Item(start: iso.date(from: "2026-10-13T21:30:00Z"), order: 1),
            Item(start: iso.date(from: "2026-10-14T08:00:00Z"), order: 3),
            Item(start: nil, order: 0)
        ]
        let index = SchoolAgendaMonth.index(items, calendar: calendar, start: { $0.start }, order: { $0.order < $1.order })
        let thirteenth = calendar.startOfDay(for: date(2026, 10, 13))
        let fourteenth = calendar.startOfDay(for: date(2026, 10, 14))
        #expect(index[thirteenth]?.map(\.order) == [1])
        #expect(index[fourteenth]?.map(\.order) == [2, 3])
        #expect(index.values.reduce(0) { $0 + $1.count } == 3)
    }

    @Test func dayMarksAreCappedAtThree() {
        #expect(SchoolAgendaMonth.marks(active: 0, closed: 0).isEmpty)
        #expect(SchoolAgendaMonth.marks(active: 2, closed: 0) == [.active, .active])
        #expect(SchoolAgendaMonth.marks(active: 1, closed: 1) == [.active, .closed])
        #expect(SchoolAgendaMonth.marks(active: 3, closed: 0) == [.active, .active, .active])
        #expect(SchoolAgendaMonth.marks(active: 5, closed: 1) == [.active, .active, .more])
        #expect(SchoolAgendaMonth.marks(active: 0, closed: 4) == [.closed, .closed, .more])
        #expect(SchoolAgendaDaySummary(active: 2, closed: 1).spokenCount == "3 leçons")
        #expect(SchoolAgendaDaySummary(active: 0, closed: 1).spokenCount == "1 leçon")
        #expect(SchoolAgendaDaySummary.empty.spokenCount.isEmpty)
    }

    @Test func memoryServesAWeekFromItsMonthOnlyForTheSameScope() {
        defer { SchoolAgendaMemory.forget() }
        SchoolAgendaMemory.forget()
        let anchor = date(2026, 10, 14)
        let month = SchoolAgendaMonth.gridRange(for: anchor, calendar: calendar)
        let week = SchoolAgendaMonth.weekRange(for: anchor, calendar: calendar)
        let readAt = Date()
        SchoolAgendaMemory.remember([], prefix: "compte:école:all", range: month, now: readAt)
        #expect(SchoolAgendaMemory.lessons(prefix: "compte:école:all", range: week, now: readAt)?.isFresh == true)
        #expect(SchoolAgendaMemory.lessons(prefix: "compte:école:all", range: week, now: readAt.addingTimeInterval(60))?.isFresh == false)
        // Un autre filtre, ou un mois que la grille ne contient pas, ne retrouve rien.
        #expect(SchoolAgendaMemory.lessons(prefix: "compte:école:moniteur", range: week, now: readAt)?.isFresh == nil)
        let next = SchoolAgendaMonth.gridRange(for: date(2026, 11, 14), calendar: calendar)
        #expect(SchoolAgendaMemory.lessons(prefix: "compte:école:all", range: next, now: readAt)?.isFresh == nil)
        SchoolAgendaMemory.forget()
        #expect(SchoolAgendaMemory.lessons(prefix: "compte:école:all", range: week, now: readAt)?.isFresh == nil)
    }
}
