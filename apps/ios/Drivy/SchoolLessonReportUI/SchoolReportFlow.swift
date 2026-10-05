import Foundation

/// Une étape de la rédaction du bilan en largeur compacte.
enum SchoolReportStep: String, CaseIterable, Identifiable, Sendable {
    case trip, competencies, report
    var id: String { rawValue }
}

/// Compétences du référentiel, celles de la leçon d’abord.
struct SchoolReportCompetencyGroups: Equatable {
    let worked: [SchoolCatalogCompetency]
    let others: [SchoolCatalogCompetency]
}

/// Règles de la rédaction du bilan : étapes, ordre, repères. Aucune n’écrit ni n’envoie quoi que ce soit.
enum SchoolReportFlowRules {
    /// Ordre du parcours. C’est le seul endroit où il se décide : l’inverser se fait ici.
    static let order: [SchoolReportStep] = [.trip, .competencies, .report]

    /// Pas d’étape vide : sans trajet ni observation, pas de revue du trajet ; sans référentiel, pas de compétences.
    /// Le texte du bilan est toujours proposé.
    static func steps(hasTrip: Bool, observationCount: Int, competencyCount: Int) -> [SchoolReportStep] {
        order.filter { step in
            switch step {
            case .trip: hasTrip || observationCount > 0
            case .competencies: competencyCount > 0
            case .report: true
            }
        }
    }

    /// Sans trajet, l’étape ne montre que les observations et porte leur nom.
    static func title(of step: SchoolReportStep, hasTrip: Bool) -> String {
        switch step {
        case .trip: hasTrip ? "Trajet" : "Observations"
        case .competencies: "Compétences"
        case .report: "Bilan"
        }
    }

    /// « 2 sur 3 » ; rien quand le parcours tient en une étape.
    static func position(of index: Int, count: Int) -> String? {
        guard count > 1, (0..<count).contains(index) else { return nil }
        return "\(index + 1) sur \(count)"
    }

    /// En tête : les compétences signalées en route, visées par un objectif ou déjà notées dans le bilan enregistré.
    /// Les autres suivent, repliées. Sans aucun repère, la liste reste entière et à plat.
    static func competencyGroups(_ competencies: [SchoolCatalogCompetency], observations: [SchoolObservation],
                                 goals: [SchoolLessonGoal], saved: [SchoolReportObservation]) -> SchoolReportCompetencyGroups {
        let marked = Set(observations.compactMap(\.competencyId)).union(goals.compactMap(\.competencyId)).union(saved.map(\.competencyId))
        let worked = competencies.filter { marked.contains($0.id) }
        guard !worked.isEmpty, worked.count < competencies.count else {
            return SchoolReportCompetencyGroups(worked: competencies, others: [])
        }
        return SchoolReportCompetencyGroups(worked: worked, others: competencies.filter { !marked.contains($0.id) })
    }

    /// « En route : Attention, Point positif » : ce que le moniteur a signalé sur cette compétence pendant la leçon.
    static func signalled(for competencyID: UUID, in observations: [SchoolObservation]) -> String? {
        var labels: [String] = []
        for observation in observations where observation.competencyId == competencyID {
            guard let label = SchoolLessonHubRules.status(of: observation)?.label, !labels.contains(label) else { continue }
            labels.append(label)
        }
        return labels.isEmpty ? nil : "En route\u{00A0}: \(labels.joined(separator: ", "))"
    }

    /// « 14:32 · Sur le trajet » : quand l’observation a été faite, et si elle a une position.
    static func observationDetail(_ observation: SchoolObservation, zone: String?) -> String? {
        var parts: [String] = []
        if let date = observation.observedDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_CH")
            formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
            formatter.dateFormat = "HH:mm"
            parts.append(formatter.string(from: date))
        }
        if observation.hasPosition { parts.append("Sur le trajet") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Libellé de l’entrée dans la rédaction depuis la fiche de la leçon.
    static func editTitle(isEmpty: Bool, unsaved: Bool) -> String {
        if unsaved { return "Reprendre le bilan" }
        return isEmpty ? "Rédiger le bilan" : "Modifier le bilan"
    }
}
