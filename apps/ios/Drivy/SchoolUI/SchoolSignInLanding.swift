import SwiftUI

/// Présentation de connexion ; l'identité et l'autorisation restent dans la racine.
/// Les quatre états (prêt, connexion en cours, échec, non configuré) gardent la même
/// charpente : la trace, la promesse, puis au plus un message au-dessus des actions.
struct SchoolSignInLanding: View {
    let isConfigured: Bool
    let isWorking: Bool
    let errorMessage: String?
    let canPresent: Bool
    let signIn: () -> Void
    let joinWithCode: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var glyphHeight: CGFloat = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                DrivyRouteGlyph()
                    .frame(height: glyphHeight)
                    .padding(DrivySpacing.l)
                    .background(DrivyTheme.canvas,
                                in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                    .accessibilityHidden(true)
                Text("Vos leçons, vos trajets, votre école.")
                    .font(.drivyScreenTitle)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !isConfigured {
                    DrivyInlineMessage(text: "La connexion n’est pas activée dans cette version.", tone: .neutral)
                        .accessibilityIdentifier("school-not-configured")
                } else if let errorMessage, !isWorking {
                    SchoolErrorNotice(message: errorMessage)
                }
            }
            .drivyPageContent(maxWidth: 600)
        }
        .background(DrivyTheme.surface)
        // Un seul grand titre : la promesse. « Drivy » reste un titre de barre discret.
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isConfigured {
                DrivyStickyActionBar {
                    Button(action: signIn) {
                        DrivyBusyLabel(title: "Se connecter", busyTitle: "Connexion…", isBusy: isWorking)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityIdentifier("school-sign-in")
                    Button(action: joinWithCode) { Label("J’ai un code", systemImage: "number") }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .accessibilityIdentifier("school-sign-in-with-code")
                }
                .disabled(isWorking || !canPresent)
            }
        }
    }
}
