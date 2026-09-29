import SwiftUI

struct SchoolJoinView: View {
    @Bindable var model: SchoolJoinWorkspace
    let openSchool: (SchoolMembership) -> Void
    var loadsOnAppear = true
    @Environment(\.dismiss) private var dismiss
    @State private var expandsRetention = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    // First read only: later operations show their progress in the action itself.
                    if model.isBusy && !model.isReady {
                        DrivyLoadingState(title: "Vérification de votre compte…")
                    }
                    if let error = model.errorMessage, model.preview == nil, !isEntering {
                        SchoolErrorNotice(message: error, retry: model.isReady ? nil : { Task { await model.load() } })
                    }
                    if model.isConfirmed { confirmed }
                    else if model.isPending { pending }
                    else if let preview = model.preview { invitation(preview) }
                    else { linkEntry }
                }
                .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
            }
            .background(DrivyTheme.surface)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { primaryAction }
            .navigationTitle("Rejoindre une école")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.disabled(model.isBusy)
                }
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
        .task { if loadsOnAppear { await model.load() } }
        .accessibilityIdentifier("join-school")
    }
    /// Entry state: the field is on screen, so a refused link is said under it.
    private var isEntering: Bool {
        model.isReady && model.preview == nil && !model.isPending && !model.isConfirmed
    }

    /// Same anatomy as the code field: permanent label, bordered field, error under it, paste.
    private var linkEntry: some View {
        let error = isEntering ? model.errorMessage : nil
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
        return VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text("Lien d’invitation")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .accessibilityHidden(true)
            TextField("Coller le lien reçu", text: $model.link)
                .keyboardType(.URL).textContentType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).onSubmit { Task { await model.inspect() } }
                .padding(.horizontal, DrivySpacing.s)
                .frame(minHeight: 52)
                .background(DrivyTheme.surface, in: shape)
                .overlay {
                    shape.strokeBorder(error == nil ? DrivyTheme.controlBorder : DrivyTheme.danger,
                                       lineWidth: error == nil ? 1 : 1.5)
                }
                .disabled(model.isBusy || !model.isReady)
                .accessibilityLabel("Lien d’invitation")
                .accessibilityHint(error ?? "")
                .accessibilityIdentifier("join-invitation-link")
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(error)
            }
            PasteButton(payloadType: String.self) { values in
                if let value = values.first, value.utf8.count <= 2_048 { model.link = value }
            }
            .accessibilityLabel("Coller le lien")
            .frame(minHeight: 44)
            .padding(.top, DrivySpacing.xs)
            .disabled(model.isBusy || !model.isReady)
        }
    }
    private func invitation(_ preview: SchoolJoinPreview) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            schoolSummary(preview)
            Divider().overlay(DrivyTheme.border)
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Text("Vos données dans l’école").font(.drivySection).accessibilityAddTraits(.isHeader)
                Text(preview.notice.noticeText).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Conservation des données", isExpanded: $expandsRetention) {
                    Text(preview.notice.retentionText).textSelection(.enabled).padding(.top, DrivySpacing.s)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DrivyContactRow(title: "Contact de l’école", value: preview.notice.contactEmail, symbol: "envelope")
            }
            Divider().overlay(DrivyTheme.border)
            Toggle(isOn: $model.acknowledgesNotice) {
                Text("J’ai pris connaissance de cette notice et je souhaite rejoindre l’école avec les rôles affichés.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("join-acknowledge")
            .fixedSize(horizontal: false, vertical: true)
            secondaryLink("Utiliser un autre lien") { model.anotherInvitation() }
        }
    }
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
    private func schoolSummary(_ preview: SchoolJoinPreview) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(preview.schoolName)
                .font(.drivyTitle)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Label(SchoolPresentation.roles(preview.roles), systemImage: "person.crop.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Label(preview.maskedEmail, systemImage: "envelope")
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !model.isConfirmed {
                Label("Valable jusqu’au \(SchoolTrainingFormatting.instant(preview.expiresAt, zone: TimeZone.current.identifier))",
                      systemImage: "clock")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
    private var pending: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.preview { schoolSummary(preview) }
            DrivyPanel {
                DrivyPendingRequest(
                    message: "La réponse de l’école n’est pas arrivée. Votre demande est conservée sur cet appareil.",
                    retry: { Task { await model.retry() } }, canRetry: !model.isBusy)
            }
        }
    }
    private var confirmed: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.preview { schoolSummary(preview) }
            DrivyInlineMessage(text: "Vous avez rejoint l’école.")
            if model.trainingNotOpened {
                DrivyInlineMessage(text: "Votre école doit encore ouvrir votre formation.", tone: .neutral)
            }
            if let member = model.member {
                Text("Accès actuel : \(SchoolPresentation.roles(member.roles))")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Actualisez vos accès pour ouvrir l’école.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            secondaryLink("Consulter une autre invitation") { model.anotherInvitation() }
        }
    }
    private var actionHint: (text: String?, tone: DrivyTone) {
        if let error = model.errorMessage, model.preview != nil { return (error, .danger) }
        if model.preview != nil && !model.isConfirmed && !model.isPending && !model.acknowledgesNotice && !model.isBusy {
            return ("Confirmez votre lecture de la notice pour rejoindre l’école.", .neutral)
        }
        return (nil, .neutral)
    }

    private var primaryAction: some View {
        let hint = actionHint
        return DrivyFormActionBar(hint: hint.text, hintTone: hint.tone) {
            if model.isConfirmed {
                if let member = model.member {
                    Button("Ouvrir mon école") { openSchool(member) }.disabled(model.isBusy)
                } else {
                    Button { Task { await model.verify() } } label: {
                        DrivyBusyLabel(title: "Actualiser mes accès", busyTitle: "Vérification…", isBusy: model.isBusy)
                    }
                    .disabled(model.isBusy)
                }
            } else if model.isPending {
                Button { Task { await model.verify() } } label: {
                    DrivyBusyLabel(title: "Vérifier auprès de l’école", busyTitle: "Vérification…", isBusy: model.isBusy)
                }
                .disabled(model.isBusy)
            } else if model.preview != nil {
                Button { Task { await model.accept() } } label: {
                    DrivyBusyLabel(title: "Rejoindre l’école", busyTitle: "Envoi…", isBusy: model.isBusy)
                }
                .disabled(!model.canAccept).accessibilityIdentifier("join-confirm")
            } else {
                Button { Task { await model.inspect() } } label: {
                    DrivyBusyLabel(title: "Continuer", busyTitle: "Vérification…", isBusy: model.isBusy && model.isReady)
                }
                .disabled(!model.canPreview).accessibilityIdentifier("join-preview")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .frame(maxWidth: DrivyLayout.compactColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.surface)
    }
}
