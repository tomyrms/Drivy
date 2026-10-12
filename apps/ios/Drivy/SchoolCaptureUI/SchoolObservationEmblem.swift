import SwiftUI

/// Pictogramme d’un thème dans la grille « Signaler » : le même dessin que sur la carte, le replay et
/// les listes (`SchoolObservationPictogram`). Le gabarit suit clair, sombre et contraste accru.
struct SchoolObservationEmblem: View {
    let theme: SchoolLiveObservationTheme
    var size: CGFloat = 40

    private var glyph: DrivyObservationGlyph {
        (SchoolObservationPictogram(title: theme.title, competencyKey: theme.competency.key) ?? .vehicle).glyph
    }

    var body: some View {
        DrivyObservationGlyphImage(glyph: glyph)
            .foregroundStyle(DrivyTheme.accent)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
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
