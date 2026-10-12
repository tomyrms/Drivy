import SwiftUI

/// Une rangée de chiffres sans carte : la valeur, puis ce qu’elle mesure, séparés d’un filet. Récapitulatif d’une
/// leçon (permis, durée, compétences, observations) et formation d’un permis (leçons, dernière, prochaine).
/// Une valeur inconnue est absente, jamais remplacée par un zéro. Un chiffre qui mène quelque part est un bouton.
/// Quand la rangée ne tient pas (grand texte, colonne étroite), deux colonnes.
struct DrivyFigureStrip: View {
    struct Item: Identifiable {
        let id: String
        let value: String
        let label: String
        /// Le permis montre son véhicule devant son code.
        var licenseCode: String? = nil
        var action: (() -> Void)? = nil
        /// Ce que fait le toucher, pour VoiceOver.
        var actionHint: String? = nil
    }

    let items: [Item]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DrivySpacing.m) {
                ForEach(items) { item in
                    cell(item)
                    if item.id != items.last?.id {
                        Divider().overlay(DrivyTheme.border).frame(maxHeight: 36)
                    }
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DrivySpacing.m, alignment: .topLeading),
                                GridItem(.flexible(), spacing: DrivySpacing.m, alignment: .topLeading)],
                      alignment: .leading, spacing: DrivySpacing.m) {
                ForEach(items) { item in cell(item) }
            }
        }
    }

    @ViewBuilder private func cell(_ item: Item) -> some View {
        let label = VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            HStack(spacing: DrivySpacing.xs) {
                if let code = item.licenseCode {
                    DrivingLicenseIcon(code: code, size: 22, relativeTo: .title3)
                }
                Text(item.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DrivyTheme.text)
            }
            Text(item.label)
                .font(.caption)
                .foregroundStyle(DrivyTheme.muted)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue(item.value)
        if let action = item.action {
            Button(action: action) { label.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(minHeight: DrivyLayout.tapTarget, alignment: .topLeading)
                .accessibilityHint(item.actionHint ?? "")
                .accessibilityIdentifier("figure-\(item.id)")
        } else {
            label
        }
    }
}
