import SwiftUI

/// Pictogramme d’un thème dans la grille « Signaler » : le même dessin que sur la carte, le replay et
/// les listes (`SchoolObservationPictogram`). Le gabarit suit clair, sombre et contraste accru.
struct SchoolObservationEmblem: View {
    let glyph: DrivyObservationGlyph
    var size: CGFloat = 40

    init(glyph: DrivyObservationGlyph, size: CGFloat = 40) {
        self.glyph = glyph
        self.size = size
    }

    init(theme: SchoolLiveObservationTheme, size: CGFloat = 40) {
        self.init(glyph: theme.glyph, size: size)
    }

    var body: some View {
        DrivyObservationGlyphImage(glyph: glyph)
            .foregroundStyle(DrivyTheme.accent)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

extension SchoolLiveObservationTheme {
    /// La clé du thème désigne son dessin ; une tuile générique le retrouve par sa compétence, puis son titre.
    var glyph: DrivyObservationGlyph {
        (SchoolObservationPictogram(themeKey: key, title: title, competencyKey: competency.key) ?? .vehicle).glyph
    }
}

extension SchoolObservationTheme {
    /// Un thème du catalogue hors d’une leçon : écran de gestion, aperçu de la grille.
    var glyph: DrivyObservationGlyph {
        (SchoolObservationPictogram(themeKey: key, title: title) ?? .vehicle).glyph
    }
}

struct SchoolMarkerEmblem: View {
    var size: CGFloat = 40
    var body: some View {
        DrivyObservationGlyphImage(glyph: .moment)
            .foregroundStyle(DrivyTheme.muted)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
