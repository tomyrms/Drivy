import Foundation

/// Affichage de l’agenda, retenu entre deux visites et deux lancements (`agenda.displayMode`).
enum SchoolAgendaDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case week, month

    static let storageKey = "agenda.displayMode"

    /// Dernier affichage choisi ; la semaine tant que rien n’est retenu.
    static var stored: SchoolAgendaDisplayMode {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(SchoolAgendaDisplayMode.init(rawValue:)) ?? .week }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    @discardableResult static func remember(_ mode: SchoolAgendaDisplayMode) -> SchoolAgendaDisplayMode {
        stored = mode
        return mode
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: "Semaine"
        case .month: "Mois"
        }
    }
}

/// Fenêtre lue par l’agenda : [start, end[, bornes à minuit dans le fuseau de l’école.
struct SchoolAgendaRange: Hashable, Sendable {
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool { start <= date && date < end }
    func contains(_ other: SchoolAgendaRange) -> Bool { start <= other.start && other.end <= end }
    /// Même règle que le serveur (`planned_end > from AND planned_start < to`).
    func overlaps(start lessonStart: Date, end lessonEnd: Date) -> Bool { lessonEnd > start && lessonStart < end }
}

/// Ce que dit un jour de la grille, sans texte : une marque par leçon, trois au plus.
enum SchoolAgendaDayMark: Equatable, Sendable {
    /// Leçon qui a lieu ou aura lieu.
    case active
    /// Leçon annulée ou manquée : elle ne remplit pas le jour.
    case closed
    /// Au-delà de trois leçons : la dernière marque s’allonge.
    case more
}

/// Contrat de l'état vide : l'action de planification reste dans l'en-tête et le jour suivant reste accessible.
struct SchoolAgendaEmptyPresentation: Equatable, Sendable {
    let mayPlan: Bool
    var showsPlanInHeading: Bool { mayPlan }
    var nextDayActionTitle: String { "Voir le jour suivant" }
}

/// Date de la dernière lecture réussie pour la projection actuellement retenue. Elle n'est exposée qu'après
/// une erreur et seulement si la portée affichée est exactement celle qui a réussi.
struct SchoolAgendaFreshness: Equatable, Sendable {
    private var success: (scope: SchoolAgendaScope, date: Date)?

    mutating func recordSuccess(scope: SchoolAgendaScope, at date: Date) { success = (scope, date) }
    mutating func reset() { success = nil }
    func retainedSuccessDate(hasError: Bool, displayedScope: SchoolAgendaScope?) -> Date? {
        guard hasError, let success, success.scope == displayedScope else { return nil }
        return success.date
    }
    /// Formatée par `SchoolDateFormat`, isolé sur le main actor comme ses appelants (vue et tests).
    @MainActor func retainedSuccessMessage(hasError: Bool, displayedScope: SchoolAgendaScope?, timeZone: String) -> String? {
        guard let date = retainedSuccessDate(hasError: hasError, displayedScope: displayedScope) else { return nil }
        return "Dernière lecture réussie le \(SchoolDateFormat.template("dMMMMyHHmm", date, zone: timeZone))."
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.success?.scope == rhs.success?.scope && lhs.success?.date == rhs.success?.date
    }
}

/// Passage en deux temps entre les deux feuilles : le callback mémorise la leçon, la fermeture du planning la consomme.
struct SchoolAgendaPlanningReturn: Equatable, Sendable {
    private var confirmedLesson: SchoolLesson?

    mutating func receive(_ lesson: SchoolLesson) { confirmedLesson = lesson }
    mutating func takeConfirmedLesson() -> SchoolLesson? {
        defer { confirmedLesson = nil }
        return confirmedLesson
    }
}

/// Calcul pur du mois et de la semaine : grille lundi d’abord, navigation, leçons par jour.
/// Tout passe par le calendrier de l’école (fuseau, `fr_CH`, lundi premier jour) : aucune
/// date n’est construite par addition de secondes, les passages à l’heure d’été restent justes.
enum SchoolAgendaMonth {
    /// La grille garde toujours six semaines : sa hauteur ne saute jamais d’un mois à l’autre.
    static let gridWeeks = 6
    static let markLimit = 3

    static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func weekRange(for date: Date, calendar: Calendar) -> SchoolAgendaRange {
        let start = startOfWeek(for: date, calendar: calendar)
        return SchoolAgendaRange(start: start, end: calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400))
    }

    /// Les six semaines affichées pour le mois de `date`, du lundi qui précède le 1er.
    static func gridRange(for date: Date, calendar: Calendar) -> SchoolAgendaRange {
        let start = startOfWeek(for: startOfMonth(for: date, calendar: calendar), calendar: calendar)
        let days = gridWeeks * 7
        return SchoolAgendaRange(start: start, end: calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86_400))
    }

    static func range(for date: Date, mode: SchoolAgendaDisplayMode, calendar: Calendar) -> SchoolAgendaRange {
        mode == .month ? gridRange(for: date, calendar: calendar) : weekRange(for: date, calendar: calendar)
    }

    /// Les 42 jours de la grille, chacun à minuit dans le fuseau de l’école.
    static func gridDays(for date: Date, calendar: Calendar) -> [Date] {
        let start = gridRange(for: date, calendar: calendar).start
        return (0..<(gridWeeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Nombre de semaines qui contiennent au moins un jour du mois (4, 5 ou 6).
    static func weeksSpanned(for date: Date, calendar: Calendar) -> Int {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let last = calendar.date(byAdding: .day, value: -1, to: month.end) else { return gridWeeks }
        let first = startOfWeek(for: month.start, calendar: calendar)
        let lastWeek = startOfWeek(for: last, calendar: calendar)
        let days = calendar.dateComponents([.day], from: first, to: lastWeek).day ?? 0
        return days / 7 + 1
    }

    /// Même jour dans un autre mois, ramené au dernier jour quand il n’existe pas (31 janvier → 28 ou 29 février).
    static func shiftingMonth(_ date: Date, by offset: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: offset, to: date) ?? date
    }

    static func isSameMonth(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }

    /// Éléments rangés par jour de début dans le fuseau de l’école, chaque jour trié par `order`.
    static func index<Item>(_ items: [Item], calendar: Calendar, start: (Item) -> Date?,
                            order: (Item, Item) -> Bool) -> [Date: [Item]] {
        var result: [Date: [Item]] = [:]
        for item in items {
            guard let date = start(item) else { continue }
            result[calendar.startOfDay(for: date), default: []].append(item)
        }
        return result.mapValues { $0.sorted(by: order) }
    }

    /// Les leçons actives d’abord, puis les closes ; au-delà de trois, la dernière marque dit « davantage ».
    static func marks(active: Int, closed: Int) -> [SchoolAgendaDayMark] {
        let active = max(active, 0), closed = max(closed, 0)
        let all = Array(repeating: SchoolAgendaDayMark.active, count: active) + Array(repeating: .closed, count: closed)
        guard all.count > markLimit else { return all }
        return Array(all.prefix(markLimit - 1)) + [.more]
    }
}
