import SwiftUI

/// Identité d’un élève : une seule présentation, déclinée selon la place qu’elle occupe.
///
/// - `page` : en tête du dossier. Le nom est le titre de l’écran.
/// - `compact` : en tête d’une fiche (leçon, bilan). Le nom précède le contenu sans le dominer.
/// - `inline` : rappel de contexte sur une page secondaire (Leçons, Progression) : une ligne, sans avatar.
///
/// Le détail reste court (formation, date) ; les informations secondaires vivent ailleurs.
/// Aux très grandes tailles de texte, l’avatar disparaît et le texte prend toute la largeur.
/// VoiceOver lit un seul élément : le nom, puis le détail. L’accessoire garde sa propre lecture.
struct DrivyLearnerIdentity<Accessory: View>: View {
    enum Variant { case page, compact, inline }

    let name: String
    let detail: String?
    let variant: Variant
    private let accessory: () -> Accessory
    @Environment(\.dynamicTypeSize) private var typeSize

    init(name: String, detail: String? = nil, variant: Variant = .compact,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.name = name
        self.detail = detail
        self.variant = variant
        self.accessory = accessory
    }

    private var shownDetail: String? {
        guard let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return detail
    }

    var body: some View {
        switch variant {
        case .inline: inlineLine
        case .page, .compact: block
        }
    }

    private var block: some View {
        // Aux très grandes tailles, l’accessoire passe sous le nom au lieu de lui disputer la largeur.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DrivySpacing.s))
        return layout {
            if !stacked {
                DrivyAvatar(name: name, size: variant == .page ? 48 : 36)
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(name)
                    .font(variant == .page ? Font.drivyTitle : Font.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let shownDetail {
                    Text(shownDetail)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            accessory()
        }
    }

    private var inlineLine: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.xs))
        return HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            layout {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let shownDetail {
                    Text(shownDetail)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            accessory()
        }
    }
}

extension DrivyLearnerIdentity where Accessory == EmptyView {
    init(name: String, detail: String? = nil, variant: Variant = .compact) {
        self.init(name: name, detail: detail, variant: variant) { EmptyView() }
    }
}
