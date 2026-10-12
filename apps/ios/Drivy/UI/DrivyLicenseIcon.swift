import SwiftUI

/// Catégorie de permis de l’OAC (RS 741.51, art. 3) : catégories, sous-catégories et catégories spéciales.
/// Seule table de correspondance entre le code reçu du serveur (`categoryCode`, texte libre) et le dessin ;
/// un code hors de cette liste (offre propre à une école, restriction) n’emprunte jamais le dessin d’une autre.
/// Planche, notes et choix : docs/implementation/icones-permis-20261012.md.
enum DrivingLicenseCategory: String, CaseIterable {
    case a, a1, m
    case b, b1, be
    case c, c1, ce, c1e
    case d, d1, de, d1e
    case f, g

    /// « B », « c1e », « C1 E » ou « Cat. BE » : la casse, les espaces et le préfixe ne changent pas la catégorie.
    init?(code: String) {
        var key = code.lowercased().filter { !$0.isWhitespace && $0 != "." }
        for prefix in ["permis", "cat"] where key.hasPrefix(prefix) { key.removeFirst(prefix.count) }
        guard let category = Self(rawValue: key) else { return nil }
        self = category
    }

    var code: String { rawValue.uppercased() }

    /// Gabarit vectoriel du catalogue (`License-*`), teinté par `foregroundStyle`.
    var assetName: String { "License-\(rawValue)" }

    /// Ce que dit VoiceOver quand l’icône est seule : le code est déjà dit par le libellé voisin.
    var spokenVehicle: String {
        switch self {
        case .a: "moto"
        case .a1: "moto légère"
        case .m: "cyclomoteur"
        case .b: "voiture"
        case .b1: "quadricycle"
        case .be: "voiture et remorque"
        case .c: "camion"
        case .c1: "camion léger"
        case .ce: "camion et remorque"
        case .c1e: "camion léger et remorque"
        case .d: "autocar"
        case .d1: "minibus"
        case .de: "autocar et remorque"
        case .d1e: "minibus et remorque"
        case .f: "véhicule lent"
        case .g: "tracteur"
        }
    }
}

/// Le dessin d’une catégorie de permis, seul ou à gauche de son libellé. Un code inconnu prend le symbole
/// neutre du permis plutôt que la voiture : rien n’est déduit d’un code que l’OAC ne définit pas.
struct DrivingLicenseIcon: View {
    enum Emphasis { case normal, selected, disabled }

    let code: String
    var emphasis: Emphasis = .normal
    /// Côté du cadre carré, suivi par la taille du texte. 16 à 48 pt : le vecteur reste net à toutes les densités.
    @ScaledMetric private var side: CGFloat
    /// Une icône posée à côté de son libellé est décorative ; seule, elle se dit.
    var isDecorative = true

    init(code: String, size: CGFloat = 24, relativeTo style: Font.TextStyle = .body,
         emphasis: Emphasis = .normal, isDecorative: Bool = true) {
        self.code = code
        self.emphasis = emphasis
        self.isDecorative = isDecorative
        _side = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    private var category: DrivingLicenseCategory? { DrivingLicenseCategory(code: code) }

    var body: some View {
        DrivingLicenseGlyph(category: category)
            .frame(width: side, height: side)
            .foregroundStyle(tint)
            .accessibilityHidden(isDecorative)
            .accessibilityLabel(category.map { "Permis \($0.code), \($0.spokenVehicle)" } ?? "Permis \(code)")
    }

    private var tint: Color {
        switch emphasis {
        case .normal: DrivyTheme.muted
        case .selected: DrivyTheme.accent
        case .disabled: DrivyTheme.disabledText
        }
    }

    /// Image nue pour un menu ou un sélecteur, qui n’affichent que des `Image` : le SVG mesure 24 pt.
    static func menuImage(code: String) -> Image {
        guard let category = DrivingLicenseCategory(code: code) else { return Image(systemName: fallbackSymbol) }
        return Image(category.assetName).renderingMode(.template)
    }

    static let fallbackSymbol = "person.text.rectangle"
}

/// Le dessin nu, redimensionnable, teinté par l’appelant.
struct DrivingLicenseGlyph: View {
    let category: DrivingLicenseCategory?

    var body: some View {
        if let category {
            Image(category.assetName).renderingMode(.template).resizable().scaledToFit()
        } else {
            Image(systemName: DrivingLicenseIcon.fallbackSymbol).resizable().scaledToFit()
                .fontWeight(.semibold).padding(2)
        }
    }
}

/// En tête d’une ligne de permis : la même pastille qu’un symbole de `DrivyEntityRow`, le véhicule à la place.
struct DrivyLicenseTile: View {
    let code: String
    var isSelected = false

    var body: some View {
        DrivingLicenseIcon(code: code, size: 26, relativeTo: .body, emphasis: isSelected ? .selected : .normal)
            .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
            .background(isSelected ? DrivyTheme.surfaceRaised : DrivyTheme.surfaceMuted, in: Circle())
    }
}

/// Valeur d’un `LabeledContent` (« Formation ») : le véhicule devant « Permis B », dans la couleur atténuée des valeurs.
struct DrivingLicenseValue: View {
    let code: String

    var body: some View {
        HStack(spacing: DrivySpacing.xs) {
            DrivingLicenseIcon(code: code, size: 22)
            Text("Permis \(code)").foregroundStyle(DrivyTheme.muted)
        }
    }
}

/// « [icône] Permis B » : la forme commune des filtres et sélecteurs de permis. Le libellé reste écrit,
/// l’icône ne porte jamais seule la catégorie. Les menus n’affichent que l’image et le texte d’un `Label`.
struct DrivingLicenseLabel: View {
    let title: String
    let code: String

    var body: some View {
        Label { Text(title) } icon: { DrivingLicenseIcon.menuImage(code: code) }
    }
}
