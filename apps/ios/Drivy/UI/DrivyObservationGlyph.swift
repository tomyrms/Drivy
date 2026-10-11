import SwiftUI

/// Pictogramme d’un signalement. Les dessins de la famille « Signaler » vivent dans le catalogue
/// (`Observation-*`, gabarits vectoriels) ; une note libre sans thème garde son symbole système.
/// Planche, notes et choix : docs/implementation/icones-signaler-20261012.md.
enum DrivyObservationGlyph: Hashable {
    case asset(String)
    case system(String)

    /// Clé stable pour les signatures d’annotations de carte.
    var key: String {
        switch self {
        case .asset(let name): name
        case .system(let name): "sf:\(name)"
        }
    }

    /// Image nue pour un menu, qui n’affiche que des `Image` : les SVG du catalogue mesurent 20 pt,
    /// la taille d’une icône de menu.
    var menuImage: Image {
        switch self {
        case .asset(let name): Image(name).renderingMode(.template)
        case .system(let name): Image(systemName: name)
        }
    }

    static let moment = DrivyObservationGlyph.asset("Observation-marker")
    static let note = DrivyObservationGlyph.system("text.bubble")
}

/// Le dessin seul, redimensionnable, teinté par `foregroundStyle`.
struct DrivyObservationGlyphImage: View {
    let glyph: DrivyObservationGlyph

    var body: some View {
        switch glyph {
        case .asset(let name):
            Image(name).renderingMode(.template).resizable().scaledToFit()
        case .system(let name):
            Image(systemName: name).resizable().scaledToFit().fontWeight(.semibold)
        }
    }
}

/// Thème d’un signalement, retrouvé depuis le titre posé par « Signaler » ou, à défaut, la clé de la
/// compétence. Les identifiants et la logique métier ne changent pas : seul le dessin en dépend.
enum SchoolObservationPictogram: String, CaseIterable {
    case vehicle, observation, rightPriority = "right-priority", signage, giveWay = "give-way", intersections
    case speed, placement, manoeuvres, motorway, anticipation

    var glyph: DrivyObservationGlyph { .asset("Observation-\(rawValue)") }

    /// `nil` quand ni la compétence ni le titre ne désignent un thème : une note libre n’emprunte pas un dessin.
    /// La compétence prime, car un texte relu peut tout dire ; le titre ne fait que préciser le sous-thème
    /// de « Priorités » (priorité à droite, signalisation, céder le passage).
    init?(title: String?, competencyKey: String? = nil) {
        let fromTitle = title.flatMap(Self.match)
        if let competencyKey, let fromKey = Self.byKey[competencyKey] {
            if fromKey == .rightPriority, let sub = fromTitle, sub == .signage || sub == .giveWay {
                self = sub
            } else {
                self = fromKey
            }
            return
        }
        guard let fromTitle else { return nil }
        self = fromTitle
    }

    private static let byKey: [String: Self] = [
        "vehicule": .vehicle, "observation": .observation, "priorites": .rightPriority, "intersections": .intersections,
        "vitesse": .speed, "placement": .placement, "manoeuvres": .manoeuvres, "parking": .manoeuvres,
        "autoroute": .motorway, "motorway": .motorway, "anticipation": .anticipation,
    ]

    /// Ordre utile : les sous-thèmes de « Priorités » passent avant le mot « priorité » seul.
    private static let byWords: [(String, Self)] = [
        ("priorite a droite", .rightPriority), ("priorite de droite", .rightPriority),
        ("ceder le passage", .giveWay), ("signalisation", .signage),
        ("giratoire", .intersections), ("intersection", .intersections), ("carrefour", .intersections),
        ("autoroute", .motorway), ("vitesse", .speed), ("stationnement", .manoeuvres), ("manoeuvre", .manoeuvres),
        ("placement", .placement), ("chaussee", .placement), ("anticipation", .anticipation),
        ("observation", .observation), ("controle", .observation), ("vehicule", .vehicle), ("priorite", .rightPriority),
    ]

    private static func match(_ title: String) -> Self? {
        let folded = title.replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "Œ", with: "oe")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr"))
        return byWords.first { folded.contains($0.0) }?.1
    }
}

extension SchoolObservationStatus {
    /// Même échelle que `ObservationStatus.tone` : l’appréciation garde ses couleurs partout.
    var tone: DrivyTone {
        switch self {
        case .attention: .warning
        case .toWorkOn: .danger
        case .positive: .success
        }
    }

    var glyph: DrivyObservationGlyph {
        switch self {
        case .attention: .asset("Observation-status-attention")
        case .toWorkOn: .asset("Observation-status-rework")
        case .positive: .asset("Observation-status-positive")
        }
    }
}

extension ObservationStatus {
    var glyph: DrivyObservationGlyph {
        switch self {
        case .attention: .asset("Observation-status-attention")
        case .toWorkOn: .asset("Observation-status-rework")
        case .positive: .asset("Observation-status-positive")
        }
    }
}

extension SchoolObservation {
    /// Thème si l’observation en a un, sinon son appréciation, sinon repère ou note.
    func glyph(competencies: [SchoolCatalogCompetency] = []) -> DrivyObservationGlyph {
        if isMarker { return .moment }
        let key = competencyId.flatMap { id in competencies.first { $0.id == id }?.key }
        if let theme = SchoolObservationPictogram(title: text, competencyKey: key) { return theme.glyph }
        return SchoolLessonHubRules.status(of: self)?.glyph ?? .note
    }
}

/// Pastille d’un signalement dans une liste ou un rail : le thème, teinté par l’appréciation
/// que le libellé voisin nomme. `filled` inverse la pastille pour l’élément en cours.
struct SchoolObservationToken: View {
    let glyph: DrivyObservationGlyph
    let tone: DrivyTone
    var side: CGFloat = 36
    var filled = false

    var body: some View {
        DrivyObservationGlyphImage(glyph: glyph)
            .foregroundStyle(filled ? (tone == .neutral ? DrivyTheme.text : tone.background) : tone.foreground)
            .frame(width: side * 0.6, height: side * 0.6)
            .frame(width: side, height: side)
            .background(filled && tone != .neutral ? tone.foreground : tone.background, in: Circle())
            .accessibilityHidden(true)
    }
}
