import SwiftUI

/// Présentation de connexion ; l'identité et l'autorisation restent dans la racine.
struct SchoolSignInLanding: View {
    let isConfigured: Bool
    let isWorking: Bool
    let errorMessage: String?
    let canPresent: Bool
    let signIn: () -> Void
    let joinWithCode: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                DrivyRouteGlyph()
                    .frame(height: 120)
                    .padding(DrivySpacing.l)
                    .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel))
                    .accessibilityHidden(true)
                Text("Vos leçons, vos trajets, votre école.")
                    .font(.drivyScreenTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if !isConfigured {
                    DrivyInlineMessage(text: "La connexion n’est pas activée dans cette version.", tone: .neutral)
                        .accessibilityIdentifier("school-not-configured")
                } else if let errorMessage {
                    SchoolErrorNotice(message: errorMessage)
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isConfigured {
                VStack(spacing: DrivySpacing.s) {
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
                .padding(.horizontal, DrivySpacing.l)
                .padding(.vertical, DrivySpacing.s)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .background(DrivyTheme.surface)
            }
        }
    }
}
