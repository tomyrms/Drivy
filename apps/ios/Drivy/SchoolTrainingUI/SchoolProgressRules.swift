import Foundation

/// La dernière leçon évaluée d’une formation, telle que la Progression la résume.
struct SchoolLastEvaluatedLesson: Equatable, Sendable {
    let lessonID: UUID
    let revisionID: UUID
    /// Début prévu de la leçon si elle est lue, sinon date de l’évaluation.
    let date: String
    /// Fuseau de la leçon si elle est lue ; sinon celui de l’école.
    let timeZone: String?
    let nextStep: String
}

/// Règles de lecture de la Progression. Le serveur ne garde que le dernier niveau publié de chaque
/// compétence : rien ici ne calcule de score, de pourcentage ni de tendance.
enum SchoolProgressRules {
    struct Source: Equatable, Sendable {
        let lessonID: UUID
        let revisionID: UUID
        let date: String
        let timeZone: String?
    }

    /// La leçon dont le bilan publié est le plus récent. Quand toutes les leçons sont lues, c’est la
    /// plus récente d’entre elles ; tant qu’il reste des pages (le serveur commence par les plus
    /// anciennes), c’est la source de l’évaluation la plus récente.
    static func lastEvaluated(lessons: [SchoolLesson], hasMore: Bool, items: [SchoolReportProgressItem]) -> Source? {
        let read = lessons
            .filter { $0.status == "COMPLETED" && $0.currentPublishedRevisionId != nil }
            .max { ($0.startsAt ?? .distantPast) < ($1.startsAt ?? .distantPast) }
            .flatMap { source(of: $0) }
        let latest = items.max { instant($0) < instant($1) }
        let observed = latest.map { item -> Source in
            // Une leçon déjà lue fait foi : sa révision en cours peut être plus récente que celle de l’évaluation.
            if let lesson = lessons.first(where: { $0.id == item.sourceLessonId }), let known = source(of: lesson) { return known }
            return Source(lessonID: item.sourceLessonId, revisionID: item.sourceRevisionId, date: item.observedAt, timeZone: nil)
        }
        return hasMore ? (observed ?? read) : (read ?? observed)
    }

    private static func source(of lesson: SchoolLesson) -> Source? {
        lesson.currentPublishedRevisionId.map {
            Source(lessonID: lesson.id, revisionID: $0, date: lesson.plannedStart, timeZone: lesson.timeZone)
        }
    }

    private static func instant(_ item: SchoolReportProgressItem) -> Date { SchoolLesson.date(item.observedAt) ?? .distantPast }

    /// « En découverte » puis « Avec accompagnement » ; dans chaque niveau, l’observation la plus ancienne d’abord.
    static func toWorkOn(_ items: [SchoolReportProgressItem]) -> [SchoolReportProgressItem] {
        items.filter { $0.level == "DISCOVERING" || $0.level == "GUIDED" }.sorted { first, second in
            let a = first.level == "DISCOVERING" ? 0 : 1, b = second.level == "DISCOVERING" ? 0 : 1
            if a != b { return a < b }
            let x = instant(first), y = instant(second)
            if x != y { return x < y }
            return first.displayLabel.localizedStandardCompare(second.displayLabel) == .orderedAscending
        }
    }

    /// Dans l’ordre du référentiel ; une compétence qui n’y figure plus passe à la fin, par libellé.
    static func independent(_ items: [SchoolReportProgressItem], order: [UUID]) -> [SchoolReportProgressItem] {
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items.filter { $0.level == "INDEPENDENT" }.sorted { first, second in
            let a = ranks[first.id] ?? Int.max, b = ranks[second.id] ?? Int.max
            if a != b { return a < b }
            return first.displayLabel.localizedStandardCompare(second.displayLabel) == .orderedAscending
        }
    }

    /// « 4 en autonomie · 3 avec accompagnement · 2 en découverte · 5 pas encore vues ». Un groupe vide n’est pas nommé.
    static func countLine(items: [SchoolReportProgressItem], unobserved: Int) -> String? {
        func count(_ level: String) -> Int { items.filter { $0.level == level }.count }
        var parts: [String] = []
        for (level, words) in [("INDEPENDENT", "en autonomie"), ("GUIDED", "avec accompagnement"), ("DISCOVERING", "en découverte")] {
            let value = count(level)
            if value > 0 { parts.append("\(value) \(words)") }
        }
        if unobserved > 0 { parts.append(unobserved == 1 ? "1 pas encore vue" : "\(unobserved) pas encore vues") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Les compétences dont le niveau en cours vient de cette leçon, dans l’ordre du référentiel.
    static func worked(in lessonID: UUID, items: [SchoolReportProgressItem], order: [UUID]) -> [SchoolReportProgressItem] {
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items.filter { $0.sourceLessonId == lessonID }.sorted { first, second in
            let a = ranks[first.id] ?? Int.max, b = ranks[second.id] ?? Int.max
            if a != b { return a < b }
            return first.displayLabel.localizedStandardCompare(second.displayLabel) == .orderedAscending
        }
    }
}
