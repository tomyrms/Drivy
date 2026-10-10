import Foundation

/// Une étape de la rédaction du bilan en largeur compacte.
enum SchoolReportStep: String, CaseIterable, Identifiable, Sendable {
    case trip, competencies, report
    var id: String { rawValue }
}

/// Ce qui ouvre la rédaction du bilan. Il n’existe aucune autre origine : ouvrir une leçon ne rédige jamais rien.
enum SchoolReportEntry: String, CaseIterable, Sendable {
    /// La leçon vient d’être terminée depuis cette fiche.
    case lessonCompleted
    /// « Rédiger le bilan », « Modifier le bilan », « Reprendre le bilan ».
    case write, edit, resume
}

/// Ce que la fiche d’une leçon terminée montre : son récapitulatif, ou la rédaction du bilan.
enum SchoolReportPresentation: Equatable, Sendable {
    case reading
    /// Rédaction en étapes poussées (largeur compacte, très grand texte).
    case steps
    /// Rédaction sur place, contexte à gauche et bilan à droite (fenêtre large).
    case sideBySide
}

/// Où se trouve l’entrée dans la rédaction sur la fiche lue.
enum SchoolReportEntryPlacement: Equatable, Sendable {
    case bottomBar(primary: Bool)
    case menu
}

/// Une liste dont la suite attend un geste.
struct SchoolReportFold<Value> {
    let shown: [Value]
    let hidden: [Value]
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

    // MARK: Lecture ou rédaction

    /// Largeur à partir de laquelle la fiche se compose en deux colonnes, hors très grand texte.
    static let wideBreakpoint: CGFloat = 900

    static func isWide(width: CGFloat, accessibilitySize: Bool) -> Bool {
        width >= wideBreakpoint && !accessibilitySize
    }

    /// Sans entrée explicite, la fiche se lit, quelle que soit sa largeur. La largeur ne choisit que la forme
    /// de la rédaction une fois celle-ci demandée ; elle ne l’ouvre jamais.
    static func presentation(entry: SchoolReportEntry?, canEdit: Bool, isWide: Bool) -> SchoolReportPresentation {
        guard canEdit, entry != nil else { return .reading }
        return isWide ? .sideBySide : .steps
    }

    /// Le geste proposé sur la fiche lue, d’après l’état du bilan.
    static func entry(isEmpty: Bool, unsaved: Bool) -> SchoolReportEntry {
        if unsaved { return .resume }
        return isEmpty ? .write : .edit
    }

    /// Une saisie pas encore envoyée domine la fiche ; un bilan à écrire reste proposé en bas, sans dominer ;
    /// un bilan enregistré se modifie depuis le menu de la barre, pour que la lecture reste une lecture.
    static func placement(of entry: SchoolReportEntry) -> SchoolReportEntryPlacement {
        switch entry {
        case .resume: .bottomBar(primary: true)
        case .write: .bottomBar(primary: false)
        case .edit, .lessonCompleted: .menu
        }
    }

    // MARK: Récapitulatif

    static let competencyFoldLimit = 5
    static let observationFoldLimit = 4

    /// Au-delà de la limite, la suite se replie. Un seul élément en trop reste affiché : le replier coûterait
    /// autant de place que le montrer.
    static func fold<Value>(_ values: [Value], limit: Int) -> SchoolReportFold<Value> {
        guard limit > 0, values.count > limit + 1 else { return SchoolReportFold(shown: values, hidden: []) }
        return SchoolReportFold(shown: Array(values.prefix(limit)), hidden: Array(values.dropFirst(limit)))
    }

    /// « Afficher les 3 autres compétences ».
    static func foldTitle(hidden: Int, noun: String) -> String {
        "Afficher les \(hidden) autres \(noun)"
    }

    /// État inhabituel des trajets de la leçon, un mot par état, sans répétition : « Partiel », « Envoi refusé ».
    @MainActor static func tripNotes(_ captures: [SchoolCaptureSession]) -> [String] {
        var notes: [String] = []
        for capture in captures {
            guard let title = SchoolTripsWorkspace.badge(capture)?.title, !notes.contains(title) else { continue }
            notes.append(title)
        }
        return notes
    }

    /// Le trajet se montre dès qu’il peut se revoir, quel que soit le statut de la leçon. Hors leçon planifiée,
    /// un trajet qui ne peut pas se revoir (retiré, refusé, pas encore envoyé) se dit quand même, en un mot ;
    /// sur une leçon planifiée, la barre du bas parle déjà du trajet en cours.
    static func showsTrip(readsLesson: Bool, hasTrack: Bool, replayableCount: Int, noteCount: Int, isPlanned: Bool) -> Bool {
        guard readsLesson else { return false }
        if hasTrack || replayableCount > 0 { return true }
        return !isPlanned && noteCount > 0
    }

    /// Bilan absent d’une leçon terminée, pour qui aurait pu le lire. L’administration seule n’en reçoit aucun :
    /// rien ne lui est dit.
    static func missingReportLine(isAuthor: Bool, isOwnLearner: Bool, canReadSharedReport: Bool) -> String? {
        if isAuthor { return "Aucun bilan pour cette leçon." }
        guard canReadSharedReport else { return nil }
        return SchoolLessonHubRules.missingReportText(isOwnLearner: isOwnLearner)
    }
}
