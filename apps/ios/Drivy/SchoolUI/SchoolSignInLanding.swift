import SwiftUI

/// Connexion dans l’app : la marque, la promesse, l’e-mail et le mot de passe, puis « Se connecter »
/// ou « J’ai un code ». Aucune page de navigateur : le mot de passe va au service de connexion de l’école.
/// L’identité et l’autorisation restent dans la racine.
struct SchoolSignInLanding: View {
    let isConfigured: Bool
    let isWorking: Bool
    let errorMessage: String?
    let signIn: (_ email: String, _ password: String) -> Void
    let joinWithCode: () -> Void
    var clearError: () -> Void = {}
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: SchoolAccountFieldID?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var canSubmit: Bool {
        isConfigured && !isWorking && email.contains("@") && !password.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                    if !typeSize.isAccessibilitySize && proxy.size.height > 560 {
                        hero(height: min(120, proxy.size.height * 0.16))
                    }
                    Text("Tes leçons, tes trajets, ton école.")
                        .font(.drivyScreenTitle)
                        .lineSpacing(DrivySpacing.xxs)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !isConfigured {
                        DrivyInlineMessage(text: "La connexion n’est pas activée dans cette version.", tone: .neutral)
                            .accessibilityIdentifier("school-not-configured")
                    } else {
                        form
                    }
                }
                .padding(.bottom, DrivySpacing.xl)
                .drivyPageContent(maxWidth: DrivyLayout.narrowColumn)
                .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(DrivyTheme.surface)
        // Un seul grand titre : la promesse. « Drivy » reste un titre de barre discret.
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isConfigured {
                DrivyStickyActionBar(maxWidth: DrivyLayout.narrowColumn) {
                    Button(action: submit) {
                        DrivyBusyLabel(title: "Se connecter", busyTitle: "Connexion…", isBusy: isWorking)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("school-sign-in")
                    Button(action: joinWithCode) { Label("J’ai un code", systemImage: "number") }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .disabled(isWorking)
                        .accessibilityIdentifier("school-sign-in-with-code")
                }
            }
        }
        .onChange(of: email) { _, _ in if errorMessage != nil { clearError() } }
        .onChange(of: password) { _, _ in if errorMessage != nil { clearError() } }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            SchoolAccountField(label: "E-mail", text: $email, kind: .email, id: .email, focus: $focus,
                               identifier: "school-sign-in-email", onSubmit: { focus = .password })
            SchoolAccountField(label: "Mot de passe", text: $password, kind: .currentPassword, id: .password, focus: $focus,
                               error: isWorking ? nil : errorMessage, identifier: "school-sign-in-password",
                               submitLabel: .go, onSubmit: submit)
        }
        .disabled(isWorking)
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        signIn(email, password)
    }

    /// Transparent symbol at sign-in; the Home Screen has its own full-bleed composition.
    private func hero(height: CGFloat) -> some View {
        DrivyBrandMark()
            .frame(width: height, height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
