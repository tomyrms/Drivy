import SwiftUI

/// Disposition de la grille « Signaler » pour un nombre quelconque de tuiles : tout le catalogue affiché, plus
/// les tuiles génériques d’un référentiel propre à l’école. Aucun nombre de thèmes n’est supposé.
/// Règle : le nombre de colonnes suit le nombre de tuiles, puis se limite à ce que la largeur permet sans passer
/// sous la largeur de tuile actuelle. Le volet montre d’emblée les douze premières tuiles ; les suivantes
/// continuent la même grille en dessous et s’atteignent en la faisant défiler. Rien ici ne lit l’écran :
/// la règle se teste sans vue. Détail : docs/implementation/signalements-ios-20261012.md.
struct SchoolSignalGridLayout: Equatable {
    let columns: Int
    let rows: Int

    /// Largeur minimale d’une tuile : celle des trois colonnes d’un iPhone de 375 pt, inchangée.
    static let minimumTileWidth: CGFloat = 100
    /// Dès la taille de texte XXL, deux lignes de libellé demandent une tuile plus large.
    static let largeTextTileWidth: CGFloat = 148
    /// Hauteur minimale d’une tuile, inchangée : jamais sous la cible tactile.
    static let minimumTileHeight: CGFloat = 80
    static let spacing = DrivySpacing.xxs
    /// Marge de la grille dans le volet.
    static let gutter = DrivySpacing.s
    /// Largeur supposée du volet avant sa première mesure : un iPhone de 393 pt.
    static let assumedWidth: CGFloat = 361
    /// Tuiles visibles à l’ouverture, sans défiler. Douze se divise par 1, 2, 3 et 4 : la fenêtre finit toujours
    /// sur une rangée pleine.
    static let immediateTileCount = 12
    /// Haut de la rangée suivante laissé visible sous la fenêtre (en plus de la marge), estompé : il dit que la
    /// grille continue sans masquer la dernière rangée de la fenêtre.
    static let peek: CGFloat = 16
    /// Hauteur du fondu au bas de la grille : l’amorce de la rangée suivante, jamais la fenêtre.
    static var fadeHeight: CGFloat { spacing + peek + gutter }

    init(tileCount: Int, width: CGFloat, textSize: DynamicTypeSize) {
        let count = max(0, tileCount)
        guard count > 0 else { columns = 1; rows = 0; return }
        // Tailles d’accessibilité : une colonne, pictogramme à gauche du libellé.
        guard !textSize.isAccessibilitySize else { columns = 1; rows = count; return }
        // Peu de tuiles : une seule rangée de tuiles larges, ou un carré de quatre. Jusqu’à douze : trois colonnes,
        // comme avant. Au-delà : quatre colonnes là où la largeur le permet (iPad, paysage), sinon des rangées de trois
        // (cinq pour treize à quinze tuiles, six pour seize à dix-huit) ; au-delà des douze premières, la grille défile.
        let wanted: Int
        switch count {
        case 1...3: wanted = count
        case 4: wanted = 2
        case 5...12: wanted = 3
        default: wanted = 4
        }
        let tile = textSize >= .xxLarge ? Self.largeTextTileWidth : Self.minimumTileWidth
        let usable = max(0, width - 2 * Self.gutter)
        let fitting = max(1, Int((usable + Self.spacing) / (tile + Self.spacing)))
        columns = min(wanted, fitting)
        rows = (count + columns - 1) / columns
    }

    /// Rangées montrées à l’ouverture : celles des douze premières tuiles.
    var visibleRows: Int { min(rows, (Self.immediateTileCount + columns - 1) / columns) }
    /// Des tuiles suivent la fenêtre : la grille défile.
    var overflows: Bool { rows > visibleRows }

    /// Hauteur de la grille à l’ouverture, toutes les tuiles ayant la même hauteur : la fenêtre, plus l’amorce
    /// de la rangée suivante quand il y en a une.
    func windowHeight(tileHeight: CGFloat) -> CGFloat {
        let window = CGFloat(visibleRows) * tileHeight + CGFloat(max(0, visibleRows - 1)) * Self.spacing
        return overflows ? window + Self.spacing + Self.peek : window
    }

    var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columns)
    }

    /// Hauteur du volet avant sa mesure réelle : en-tête, fenêtre de la grille, appréciations. Une rangée compte
    /// un libellé sur deux lignes, réservées à chaque tuile.
    static func estimatedPaletteHeight(tileCount: Int, width: CGFloat, textSize: DynamicTypeSize) -> CGFloat {
        let layout = SchoolSignalGridLayout(tileCount: tileCount, width: width, textSize: textSize)
        let row: CGFloat
        switch textSize {
        case .xSmall, .small, .medium, .large: row = 84
        case .xLarge: row = 90
        case .xxLarge: row = 96
        default: row = 104
        }
        let header = DrivyLayout.tapTarget + 2 * DrivySpacing.xs
        let appraisals: CGFloat = 76 + 2 * DrivySpacing.xs + 1
        let grid = layout.windowHeight(tileHeight: row)
        return header + grid + gutter + appraisals
    }
}

/// Contenu d’une tuile de thème, commun à « Signaler » et à son aperçu dans l’écran de gestion.
/// Hors tailles d’accessibilité, chaque libellé réserve deux lignes : toutes les tuiles ont la même hauteur,
/// la grille reste régulière et sa fenêtre se calcule d’après une seule tuile.
struct SchoolSignalTileLabel: View {
    let glyph: DrivyObservationGlyph
    let title: String
    var isSelected = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: DrivySpacing.s) {
                    SchoolObservationEmblem(glyph: glyph, size: 32)
                    label.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: DrivySpacing.xxs) {
                    SchoolObservationEmblem(glyph: glyph, size: 28)
                    label.multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, DrivySpacing.xs)
        .padding(.vertical, DrivySpacing.xs)
        .frame(maxWidth: .infinity, minHeight: SchoolSignalGridLayout.minimumTileHeight)
        .background(isSelected ? DrivyTheme.accentSoft : .clear, in: shape)
        .overlay { shape.strokeBorder(isSelected ? DrivyTheme.accent : .clear, lineWidth: 1.5) }
        .contentShape(shape)
    }

    @ViewBuilder private var label: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Un libellé plus long (compétence d’un référentiel propre) se resserre avant d’être tronqué.
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.85)
        }
    }
}

/// La grille telle qu’elle apparaît en leçon, sans commande : aperçu de l’écran de gestion et planche de la
/// galerie. Les tuiles viennent des thèmes affichés, dans l’ordre donné.
struct SchoolSignalGridPreview: View {
    let themes: [SchoolObservationTheme]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width = SchoolSignalGridLayout.assumedWidth

    private var visible: [SchoolObservationTheme] { themes.filter(\.visible) }

    var body: some View {
        let layout = SchoolSignalGridLayout(tileCount: visible.count, width: width, textSize: dynamicTypeSize)
        return LazyVGrid(columns: layout.gridItems, spacing: SchoolSignalGridLayout.spacing) {
            ForEach(visible) { theme in
                SchoolSignalTileLabel(glyph: theme.glyph, title: theme.title)
            }
        }
        .padding(.horizontal, SchoolSignalGridLayout.gutter)
        .padding(.vertical, SchoolSignalGridLayout.gutter)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Une image de la grille : VoiceOver lit la liste réglable, pas des tuiles inertes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu de la grille")
        .accessibilityValue(visible.map(\.title).joined(separator: ", "))
    }
}
