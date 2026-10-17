import SwiftUI

/// « J’ai un code » : le code (ou le lien reçu), puis la création du compte ; « J’ai déjà un compte »
/// connecte un compte existant en gardant le code pour la suite.
struct SchoolAccessCodeView: View {
    @Bindable var model: SchoolAccessWorkspace
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: SchoolAccountFieldID?
    @ScaledMetric(relativeTo: .title2) private var codeSize: CGFloat = 28

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    switch model.step {
                    case .code: codeStep
                    case .register: registerStep
                    case .signIn: signInStep
                    }
                }
                .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
                .disabled(model.isBusy)
            }
            .background(DrivyTheme.surface)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
        .onAppear { focus = model.step == .code ? .code : .firstName }
        .onChange(of: model.step) { _, step in
            switch step {
            case .code: focus = .code
            case .register: focus = .firstName
            case .signIn: focus = .email
            }
        }
        .accessibilityIdentifier("access-code")
    }

    private var title: String {
        switch model.step {
        case .code: "J’ai un code"
        case .register: model.registerTitle
        case .signIn: "Se connecter"
        }
    }

    // MARK: Code

    private var codeBinding: Binding<String> {
        Binding(get: { model.codeText }, set: { value in
            // Un lien collé reste entier ; un code tapé se met en forme XXXX-XXXX.
            model.codeText = value.contains("/") ? value : SchoolInvitationCode.formatted(value)
        })
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                SchoolJoinFieldBlock(label: "Code ou lien reçu", error: model.errorMessage, errorIdentifier: "access-code-error") {
                    TextField("XXXX-XXXX", text: codeBinding,
                              prompt: Text("XXXX-XXXX").fontWeight(.regular).foregroundStyle(DrivyTheme.muted))
                        .font(.system(size: codeSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DrivyTheme.text)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.oneTimeCode)
                        .submitLabel(.go)
                        .onSubmit { Task { await model.inspect() } }
                        .focused($focus, equals: .code)
                        .schoolJoinFieldChrome(hasError: model.errorMessage != nil, isFocused: focus == .code, minHeight: 64)
                        .accessibilityLabel("Code ou lien reçu")
                        .accessibilityIdentifier("access-code-field")
                }
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first, value.utf8.count <= 2_048 { codeBinding.wrappedValue = value }
                }
                .accessibilityLabel("Coller le code ou le lien")
                .frame(minHeight: DrivyLayout.tapTarget)
            }
            SchoolJoinTextLink(title: "J’ai déjà un compte", isBusy: model.isBusy) {
                Task { await model.continueWithExistingAccount() }
            }
                .accessibilityIdentifier("access-code-sign-in")
        }
    }

    // MARK: Création du compte

    private var registerStep: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if let message = model.errorMessage { SchoolErrorNotice(message: message) }
            HStack(alignment: .top, spacing: DrivySpacing.s) {
                SchoolAccountField(label: "Prénom", text: $model.firstName, kind: .givenName, id: .firstName, focus: $focus,
                                   identifier: "access-first-name", onSubmit: { focus = .lastName })
                SchoolAccountField(label: "Nom", text: $model.lastName, kind: .familyName, id: .lastName, focus: $focus,
                                   identifier: "access-last-name", onSubmit: { focus = .email })
            }
            SchoolAccountField(label: "E-mail", text: $model.email, kind: .email, id: .email, focus: $focus,
                               identifier: "access-email", onSubmit: { focus = .password })
            SchoolAccountField(label: "Mot de passe", text: $model.password, kind: .newPassword, id: .password, focus: $focus,
                               hint: "8 caractères au moins", identifier: "access-password", submitLabel: .go,
                               onSubmit: { Task { await model.register() } })
            SchoolJoinTextLink(title: "J’ai déjà un compte", isBusy: model.isBusy) { model.show(.signIn) }
                .accessibilityIdentifier("access-has-account")
        }
    }

    // MARK: Connexion avec le code gardé

    private var signInStep: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if let message = model.errorMessage { SchoolErrorNotice(message: message) }
            SchoolAccountField(label: "E-mail", text: $model.email, kind: .email, id: .email, focus: $focus,
                               identifier: "access-sign-in-email", onSubmit: { focus = .password })
            SchoolAccountField(label: "Mot de passe", text: $model.password, kind: .currentPassword, id: .password, focus: $focus,
                               identifier: "access-sign-in-password", submitLabel: .go,
                               onSubmit: { Task { await model.signIn() } })
            SchoolJoinTextLink(title: "Créer un compte", isBusy: model.isBusy) { model.show(.register) }
                .accessibilityIdentifier("access-create-account")
        }
    }

    private var actionBar: some View {
        DrivyFormActionBar {
            switch model.step {
            case .code:
                Button { Task { await model.inspect() } } label: {
                    DrivyBusyLabel(title: "Continuer", busyTitle: "Vérification…", isBusy: model.isBusy)
                }
                .disabled(!model.canInspect)
                .accessibilityIdentifier("access-code-continue")
            case .register:
                Button { Task { await model.register() } } label: {
                    DrivyBusyLabel(title: "Créer mon compte", busyTitle: "Création…", isBusy: model.isBusy)
                }
                .disabled(!model.canRegister)
                .accessibilityIdentifier("access-register")
            case .signIn:
                Button { Task { await model.signIn() } } label: {
                    DrivyBusyLabel(title: "Se connecter", busyTitle: "Connexion…", isBusy: model.isBusy)
                }
                .disabled(!model.canSignIn)
                .accessibilityIdentifier("access-sign-in")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .frame(maxWidth: DrivyLayout.compactColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.surface)
    }
}
