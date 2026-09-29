import SwiftUI

/// Rejoindre une école avec le code reçu du moniteur : un champ, l’école, « Rejoindre ».
struct SchoolCodeJoinView: View {
    @Bindable var model: SchoolCodeJoinWorkspace
    let openSchool: (SchoolMembership) -> Void
    /// An e-mail invitation link is still accepted, on its own screen.
    var useLink: (() -> Void)? = nil
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
                    else if model.isBusy { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
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
        .interactiveDismissDisabled(model.isBusy || model.isPending)
        .task {
            await model.load()
            if model.isReady && model.preview == nil && !model.isPending { fieldFocused = true }
        }
        .accessibilityIdentifier("join-school-code")
    }

    private var codeBinding: Binding<String> {
        Binding(get: { model.code }, set: { model.code = SchoolInvitationCode.formatted($0) })
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            Text("Code d’invitation")
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
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
                .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
                        .strokeBorder(model.isMistyped ? DrivyTheme.danger : DrivyTheme.controlBorder, lineWidth: 1)
                }
                .disabled(model.isBusy)
                .accessibilityLabel("Code d’invitation")
                .accessibilityIdentifier("join-code-field")
            if let useLink {
                Button(action: useLink) {
                    Text("J’ai un lien d’invitation")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.isBusy ? DrivyTheme.disabledText : DrivyTheme.accent)
                .disabled(model.isBusy)
                .accessibilityIdentifier("join-use-link")
            }
        }
    }

    private func summary(_ preview: SchoolCodePreview) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text(preview.schoolName)
                    .font(.drivyTitle)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(details(preview))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
            }
            .accessibilityElement(children: .combine)
            if !model.isConfirmed && !model.isPending {
                Button { model.anotherCode() } label: {
                    Text("Autre code")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.isBusy ? DrivyTheme.disabledText : DrivyTheme.accent)
                .disabled(model.isBusy)
            }
        }
    }

    private func details(_ preview: SchoolCodePreview) -> String {
        var parts = [SchoolPresentation.roles(preview.roles)]
        if let category = preview.trainingCategoryCode { parts.append("Permis \(category)") }
        return parts.joined(separator: " · ")
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.record?.preview { summary(preview) }
            DrivyPanel {
                DrivyPendingRequest(
                    message: "La réponse de l’école n’est pas arrivée. Votre demande est gardée sur cet appareil : vérifiez-la.",
                    verify: { Task { await model.verify() } }, canVerify: !model.isBusy,
                    verifyIdentifier: "join-code-verify")
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

    private var hint: (text: String?, tone: DrivyTone) {
        if let error = model.errorMessage, model.isReady { return (error, .danger) }
        if model.isMistyped && model.preview == nil { return ("Vérifiez le code : il ne contient ni I, ni O, ni 0, ni 1.", .danger) }
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
            } else if model.preview != nil {
                Button { Task { await model.accept() } } label: {
                    DrivyBusyLabel(title: "Rejoindre", busyTitle: "Envoi…", isBusy: model.isBusy)
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
    }
}

/// Compte sans école : un seul geste, saisir le code reçu du moniteur.
struct SchoolWithoutSchoolView: View {
    let joinSchool: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Aucune école", systemImage: "building.2")
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
