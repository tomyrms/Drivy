import SwiftUI

/// Les textes de confidentialité d'une école, lus de la même façon partout (analyse du 13 octobre 2026) :
/// trois lignes fixes sur le GPS, puis le texte complet de l'école dans une feuille. L'élève lit « Tes données »,
/// le moniteur « Confidentialité » : c'est le même texte, celui que l'élève a lu.
struct SchoolPrivacyText: Equatable {
    let notice: String
    let retention: String
    let contact: String?
}

/// Ce que l'accord GPS engage, en trois lignes écrites par Drivy. Aucune durée : rien ne supprime encore les trajets
/// automatiquement, et l'écran ne promet pas ce que l'école ne fait pas.
struct SchoolGPSPromise: View {
    var addressesLearner = true
    var requiresGPS = false

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            line("location.fill", "Position de l’appareil du moniteur, pendant la leçon")
            line("eye", addressesLearner ? "Visible par toi et ton école" : "Visible par l’élève et l’école")
            line("location.slash", requiresGPS ? "Sans accord, pas de départ GPS dans Drivy. Le compte et les rendez-vous restent accessibles." : "Le choix GPS se modifie depuis le compte")
        }
        .font(.subheadline)
        .foregroundStyle(DrivyTheme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
    }
}

/// Le lien vers le texte complet : même titre et même feuille sur tous les écrans.
struct SchoolPrivacyLink: View {
    let text: SchoolPrivacyText
    var addressesLearner = true
    var identifier = "privacy-link"
    @State private var showsText = false

    private var title: String { addressesLearner ? "Tes données" : "Confidentialité" }

    var body: some View {
        Button(title) { showsText = true }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .frame(minHeight: DrivyLayout.tapTarget)
            // Dans une ligne de formulaire, seul ce bouton répond au toucher, pas toute la ligne.
            .buttonStyle(.borderless)
            .accessibilityIdentifier(identifier)
            .sheet(isPresented: $showsText) { SchoolPrivacySheet(title: title, text: text) }
    }
}

struct SchoolPrivacySheet: View {
    let title: String
    let text: SchoolPrivacyText
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    Text(text.notice)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        Text("Conservation")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(text.retention)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let contact = text.contact {
                        DrivyContactRow(title: "Contact pour les données", value: contact, symbol: "envelope")
                    }
                }
                .foregroundStyle(DrivyTheme.text)
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .tint(DrivyTheme.accent)
    }
}
