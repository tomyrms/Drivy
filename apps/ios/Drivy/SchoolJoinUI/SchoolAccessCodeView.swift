import SwiftUI

/// « J’ai un code » : le code (ou le lien reçu), puis la création du compte ; « J’ai déjà un compte »
/// connecte un compte existant en gardant le code pour la suite.
struct SchoolAccessCodeView: View {
    @Bindable var model: SchoolAccessWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focus: SchoolAccountFieldID?
    @State private var recovering = false
    @State private var checkedSignInFields: Set<SchoolAccountFieldID> = []
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
            .sheet(isPresented: $recovering) {
                SchoolAccountRecoveryView(client: model.recoveryClient)
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
        .onAppear { focus = model.step == .code ? .code : model.step == .register ? .firstName : .email }
        .onChange(of: model.step) { _, step in
            checkedSignInFields = []
            switch step {
            case .code: focus = .code
            case .register: focus = .firstName
            case .signIn: focus = .email
            }
        }
        .onChange(of: model.email) { _, _ in model.credentialsDidChange() }
        .onChange(of: model.password) { _, _ in model.credentialsDidChange() }
        .onChange(of: focus) { previous, _ in
            if model.step == .signIn, let previous { checkedSignInFields.insert(previous) }
        }
        .onChange(of: model.codeInputError ?? model.errorMessage) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
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
            model.updateCode(value)
        })
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                SchoolJoinFieldBlock(label: "Code ou lien reçu", error: model.codeInputError ?? model.errorMessage, errorIdentifier: "access-code-error") {
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
                        .schoolJoinFieldChrome(hasError: model.codeInputError != nil || model.errorMessage != nil, isFocused: focus == .code, minHeight: 64)
                        .accessibilityLabel("Code ou lien reçu")
                        .accessibilityHint(model.codeInputError ?? model.errorMessage ?? "")
                        .accessibilityIdentifier("access-code-field")
                }
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first { model.pasteCode(value) }
                }
                .accessibilityLabel("Coller le code ou le lien")
                .accessibilityIdentifier("access-code-paste")
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
            let names = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.m))
                : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.s))
            names {
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
            editCode
        }
    }

    // MARK: Connexion avec le code gardé

    private var signInStep: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if let message = model.errorMessage {
                SchoolErrorNotice(message: message).accessibilityIdentifier("access-sign-in-error")
            }
            SchoolAccountField(label: "E-mail", text: $model.email, kind: .email, id: .email, focus: $focus,
                               error: checkedSignInFields.contains(.email) ? SchoolSignInValidation.emailIssue(model.email) : nil,
                               identifier: "access-sign-in-email", onSubmit: { focus = .password })
            SchoolAccountField(label: "Mot de passe", text: $model.password, kind: .currentPassword, id: .password, focus: $focus,
                               error: checkedSignInFields.contains(.password) ? SchoolSignInValidation.passwordIssue(model.password) : nil,
                               identifier: "access-sign-in-password", submitLabel: .go,
                               onSubmit: submitSignIn)
            SchoolJoinTextLink(title: "Mot de passe oublié", isBusy: model.isBusy) {
                model.prepareRecovery(); focus = nil; recovering = true
            }
            .accessibilityIdentifier("access-recover")
            SchoolJoinTextLink(title: "Créer un compte", isBusy: model.isBusy) { model.show(.register) }
                .accessibilityIdentifier("access-create-account")
            editCode
        }
    }

    private var editCode: some View {
        SchoolJoinTextLink(title: "Modifier le code", isBusy: model.isBusy) { model.show(.code) }
            .accessibilityIdentifier("access-edit-code")
    }

    private func submitSignIn() {
        guard !model.isBusy else { return }
        checkedSignInFields.formUnion([.email, .password])
        guard model.canSignIn else {
            focus = SchoolSignInValidation.emailIssue(model.email) != nil ? .email : .password
            return
        }
        focus = nil
        Task { await model.signIn() }
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
                Button(action: submitSignIn) {
                    DrivyBusyLabel(title: "Se connecter", busyTitle: "Connexion…", isBusy: model.isBusy)
                }
                .disabled(!model.canSignIn)
                .accessibilityHint(model.isBusy ? "Connexion en cours." : (SchoolSignInValidation.emailIssue(model.email)
                    ?? SchoolSignInValidation.passwordIssue(model.password) ?? ""))
                .accessibilityIdentifier("access-sign-in")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .frame(maxWidth: DrivyLayout.compactColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.surface)
    }
}
