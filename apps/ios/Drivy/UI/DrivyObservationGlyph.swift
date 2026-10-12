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

/// Thème d’un signalement : sa clé quand l’observation la porte, sinon la clé de la compétence et le titre
/// posé par « Signaler ». La valeur brute est la clé du catalogue et le nom du dessin (`Observation-<clé>`).
/// Les identifiants et la logique métier ne changent pas : seul le dessin en dépend, jamais l’affichage réglé
/// par l’école — un thème masqué garde son dessin partout où il a servi.
enum SchoolObservationPictogram: String, CaseIterable {
    case vehicle, observation, rightPriority = "right-priority", signage, giveWay = "give-way", intersections
    case speed, placement, manoeuvres, motorway, anticipation
    case indicators, followingDistance = "following-distance", braking, laneChange = "lane-change"

    var glyph: DrivyObservationGlyph { .asset("Observation-\(rawValue)") }

    /// `nil` quand rien ne désigne un thème : une note libre n’emprunte pas un dessin.
    /// La clé du thème prime : elle ne dépend ni du texte, que le moniteur peut réécrire, ni de l’ordre.
    /// Sans clé (observation ancienne, école qui n’a pas répondu), la compétence prime sur le texte, qui ne
    /// fait que préciser un sous-thème de cette compétence (« Signalisation » pour « Priorités »,
    /// « Clignotants » pour « Observation et contrôles »…).
    init?(themeKey: String? = nil, title: String?, competencyKey: String? = nil) {
        if let themeKey, let fromTheme = Self(rawValue: themeKey) {
            self = fromTheme
            return
        }
        let fromTitle = title.flatMap(Self.match)
        if let competencyKey, let fromKey = Self.byKey[competencyKey] {
            if let sub = fromTitle, Self.refinements[fromKey]?.contains(sub) == true {
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

    /// Sous-thèmes qu’un titre peut préciser à l’intérieur d’une compétence.
    private static let refinements: [Self: Set<Self>] = [
        .rightPriority: [.signage, .giveWay], .observation: [.indicators], .speed: [.followingDistance],
        .vehicle: [.braking], .placement: [.laneChange],
    ]

    /// Ordre utile : les sous-thèmes passent avant le mot plus large de leur compétence (« priorité », « vitesse »,
    /// « placement »…).
    private static let byWords: [(String, Self)] = [
        ("priorite a droite", .rightPriority), ("priorite de droite", .rightPriority),
        ("ceder le passage", .giveWay), ("signalisation", .signage),
        ("clignotant", .indicators), ("distance de securite", .followingDistance),
        ("freinage", .braking), ("changement de voie", .laneChange),
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
        if let theme = SchoolObservationPictogram(themeKey: themeKey, title: text, competencyKey: key) { return theme.glyph }
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
            .foregroundStyle(filled ? (tone == .neutral ? DrivyTheme.text : tone.background) : tone.signal)
            .frame(width: side * 0.6, height: side * 0.6)
            .frame(width: side, height: side)
            .background(filled && tone != .neutral ? tone.signal : tone.background, in: Circle())
            .accessibilityHidden(true)
    }
}
