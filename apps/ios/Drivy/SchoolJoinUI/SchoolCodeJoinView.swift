import SwiftUI

/// Rejoindre une école avec le code reçu du moniteur : un champ, l’école, « Rejoindre ».
struct SchoolCodeJoinView: View {
    @Bindable var model: SchoolCodeJoinWorkspace
    let openSchool: (SchoolMembership) -> Void
    /// An e-mail invitation link is still accepted, on its own screen.
    var useLink: (() -> Void)? = nil
    var loadsOnAppear = true
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool
    @ScaledMetric(relativeTo: .title) private var codeSize: CGFloat = 32

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if let error = model.errorMessage, !model.isReady {
                        SchoolErrorNotice(message: error, retry: { Task { await model.load() } })
                    }
                    if model.isConfirmed { confirmed }
                    else if model.isPending { pending }
                    else if let preview = model.preview { summary(preview) }
                    else if model.isReady { entry }
                    else if model.isBusy { DrivyLoadingState(title: "Vérification de votre compte…") }
                }
                .drivyPageContent(maxWidth: 560)
            }
            .background(DrivyTheme.surface)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle("Rejoindre une école")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
        .task {
            guard loadsOnAppear else { return }
            await model.load()
            if model.isReady && model.preview == nil && !model.isPending { fieldFocused = true }
        }
        .accessibilityIdentifier("join-school-code")
    }

    private var codeBinding: Binding<String> {
        Binding(get: { model.code }, set: { model.code = SchoolInvitationCode.formatted($0) })
    }

    /// Entry state: the field is on screen, so what is wrong with the code is said under it.
    private var isEntering: Bool {
        model.isReady && model.preview == nil && !model.isPending && !model.isConfirmed
    }

    /// Refused or mistyped code, shown under the field rather than in the bottom bar.
    private var fieldError: String? {
        guard isEntering else { return nil }
        if let error = model.errorMessage { return error }
        if model.isMistyped { return "Vérifiez le code : il ne contient ni I, ni O, ni 0, ni 1." }
        return nil
    }

    private var entry: some View {
        let error = fieldError
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
        return VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text("Code d’invitation")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .accessibilityHidden(true)
            TextField("XXXX-XXXX", text: codeBinding)
                .font(.system(size: codeSize, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.oneTimeCode)
                .submitLabel(.go)
                .onSubmit { Task { await model.inspect() } }
                .focused($fieldFocused)
                .padding(DrivySpacing.m)
                .frame(minHeight: 64)
                .background(DrivyTheme.surface, in: shape)
                .overlay {
                    shape.strokeBorder(error == nil ? DrivyTheme.controlBorder : DrivyTheme.danger,
                                       lineWidth: error == nil ? 1 : 1.5)
                }
                .disabled(model.isBusy)
                .accessibilityLabel("Code d’invitation")
                .accessibilityHint(error ?? "")
                .accessibilityIdentifier("join-code-field")
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(error)
                    .accessibilityIdentifier("join-code-field-error")
            }
            // Same paste control as the invitation link; the field formats what is pasted.
            PasteButton(payloadType: String.self) { values in
                if let value = values.first, value.utf8.count <= 64 { model.code = SchoolInvitationCode.formatted(value) }
            }
            .accessibilityLabel("Coller le code")
            .frame(minHeight: 44)
            .padding(.top, DrivySpacing.xs)
            .disabled(model.isBusy)
            if let useLink {
                secondaryLink("J’ai un lien d’invitation", action: useLink)
                    .accessibilityIdentifier("join-use-link")
            }
        }
    }

    /// Text action of the join screens: same size, colour and 44 pt target in both sheets.
    private func secondaryLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.isBusy ? DrivyTheme.disabledText : DrivyTheme.accent)
        .disabled(model.isBusy)
    }

    /// Same school summary as the invitation link: name, then one labelled line per fact.
    private func summary(_ preview: SchoolCodePreview) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text(preview.schoolName)
                    .font(.drivyTitle)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Label(SchoolPresentation.roles(preview.roles), systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let categories = categories(preview) {
                    Label(categories, systemImage: "car")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if !model.isConfirmed && !model.isPending {
                secondaryLink("Saisir un autre code") { model.anotherCode() }
            }
        }
    }

    private func categories(_ preview: SchoolCodePreview) -> String? {
        guard !preview.categories.isEmpty else { return nil }
        return "Permis \(Array(Set(preview.categories)).sorted().joined(separator: ", "))"
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.record?.preview { summary(preview) }
            DrivyPanel {
                DrivyPendingRequest(
                    message: "La réponse de l’école n’est pas arrivée. Votre demande est conservée sur cet appareil.")
            }
        }
    }

    private var confirmed: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.record?.preview { summary(preview) }
            DrivyInlineMessage(text: "Vous avez rejoint l’école.")
            if model.trainingNotOpened {
                DrivyInlineMessage(text: "Votre école doit encore ouvrir votre formation.", tone: .neutral)
            }
        }
    }

    /// Once the field is gone (preview, pending), a failure is said next to the action.
    private var hint: (text: String?, tone: DrivyTone) {
        if let error = model.errorMessage, model.isReady, !isEntering { return (error, .danger) }
        return (nil, .neutral)
    }

    private var actionBar: some View {
        let hint = hint
        return DrivyFormActionBar(hint: hint.text, hintTone: hint.tone) {
            if model.isConfirmed {
                if let member = model.member {
                    Button("Ouvrir mon école") { openSchool(member) }
                        .accessibilityIdentifier("join-code-open")
                }
            } else if model.isPending {
                Button { Task { await model.verify() } } label: {
                    DrivyBusyLabel(title: "Vérifier auprès de l’école", busyTitle: "Vérification…", isBusy: model.isBusy)
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("join-code-verify")
            } else if model.preview != nil {
                Button { Task { await model.accept() } } label: {
                    DrivyBusyLabel(title: "Rejoindre l’école", busyTitle: "Envoi…", isBusy: model.isBusy)
                }
                .disabled(!model.canAccept)
                .accessibilityIdentifier("join-code-confirm")
            } else {
                Button { Task { await model.inspect() } } label: {
                    DrivyBusyLabel(title: "Continuer", busyTitle: "Vérification…", isBusy: model.isBusy)
                }
                .disabled(!model.canPreview)
                .accessibilityIdentifier("join-code-preview")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.surface)
    }
}

/// Compte sans école : un seul geste, saisir le code reçu du moniteur.
struct SchoolWithoutSchoolView: View {
    let joinSchool: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Aucune école", systemImage: "building.2")
        } description: {
            Text("Saisissez le code reçu de votre moniteur.")
        } actions: {
            if let joinSchool {
                Button(action: joinSchool) { Label("J’ai un code", systemImage: "number") }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier("join-with-code")
            }
        }
        .background(DrivyTheme.canvas)
    }
}
