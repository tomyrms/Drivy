import SwiftUI

struct SchoolJoinView: View {
    @Bindable var model: SchoolJoinWorkspace
    let openSchool: (SchoolMembership) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var expandsRetention = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if model.isBusy {
                        ProgressView("Vérification auprès de l’école…").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    if let error = model.errorMessage {
                        SchoolErrorNotice(message: error, retry: model.isReady ? nil : { Task { await model.load() } })
                    }
                    if model.isConfirmed { confirmed }
                    else if model.isPending { pending }
                    else if let preview = model.preview { invitation(preview) }
                    else { linkEntry }
                }
                .drivyPageContent()
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
        .task { await model.load() }
        .accessibilityIdentifier("join-school")
    }
    private var linkEntry: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text("Lien d’invitation").font(.drivyTitle).accessibilityAddTraits(.isHeader)
                Text("Utilisez le compte correspondant à l’adresse destinataire de l’invitation.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SecureField("Coller le lien reçu", text: $model.link)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).onSubmit { Task { await model.inspect() } }
                .padding(DrivySpacing.m)
                .frame(minHeight: 52)
                .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
                        .strokeBorder(DrivyTheme.controlBorder, lineWidth: 1)
                }
                .disabled(model.isBusy || !model.isReady)
                .accessibilityLabel("Lien d’invitation")
                .accessibilityIdentifier("join-invitation-link")
            PasteButton(payloadType: String.self) { values in
                if let value = values.first, value.utf8.count <= 2_048 { model.link = value }
            }
            .disabled(model.isBusy || !model.isReady)
            Text("Vous relirez l’école, les rôles et la notice avant d’accepter.")
                .font(.footnote).foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func invitation(_ preview: SchoolJoinPreview) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            schoolSummary(preview)
            Divider().overlay(DrivyTheme.border)
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Text("Vos données dans l’école").font(.drivySection).accessibilityAddTraits(.isHeader)
                Text("Notice · version \(preview.notice.version)").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
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
            secondaryLink("Utiliser un autre lien") { model.anotherInvitation() }
        }
    }
    private func secondaryLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.isBusy ? DrivyTheme.disabledText : DrivyTheme.accent)
        .disabled(model.isBusy)
    }
    private func schoolSummary(_ preview: SchoolJoinPreview) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(preview.schoolName).font(.drivyTitle).fixedSize(horizontal: false, vertical: true)
            Label(SchoolPresentation.roles(preview.roles), systemImage: "person.crop.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
            Label(preview.maskedEmail, systemImage: "envelope").font(.subheadline).foregroundStyle(DrivyTheme.muted)
            if !model.isConfirmed {
                Text("Invitation valable jusqu’au \(SchoolTrainingFormatting.instant(preview.expiresAt, zone: TimeZone.current.identifier))")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var pending: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.preview { schoolSummary(preview) }
            DrivyPanel {
                DrivyPendingRequest(
                    message: "Votre demande est conservée sur cet appareil. Vous pouvez fermer cet écran et revenir la vérifier avec ce compte.",
                    reference: model.record?.operationID,
                    retry: { Task { await model.retry() } }, canRetry: !model.isBusy)
            }
        }
    }
    private var confirmed: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.preview { schoolSummary(preview) }
            DrivyInlineMessage(text: "Votre invitation a été acceptée.")
            if let member = model.member {
                Text("Accès actuel : \(SchoolPresentation.roles(member.roles))")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            } else {
                Text("La confirmation est conservée. Actualisez vos accès pour ouvrir l’école.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            if let receipt = model.record?.receipt {
                DisclosureGroup("Confirmation enregistrée") {
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Text(receipt.operationId.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                        Text(SchoolTrainingFormatting.instant(receipt.committedAt, zone: TimeZone.current.identifier)).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DrivySpacing.xs)
                }.font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            secondaryLink("Une autre invitation") { model.anotherInvitation() }
        }
    }
    private var actionHint: (text: String?, tone: DrivyTone) {
        if let error = model.errorMessage, model.preview != nil { return (error, .danger) }
        if model.preview != nil && !model.isConfirmed && !model.isPending && !model.acknowledgesNotice && !model.isBusy {
            return ("Confirmez votre lecture de la notice pour accepter.", .neutral)
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
                    Button("Actualiser mes accès") { Task { await model.verify() } }.disabled(model.isBusy)
                }
            } else if model.isPending {
                Button("Vérifier auprès de l’école") { Task { await model.verify() } }.disabled(model.isBusy)
            } else if model.preview != nil {
                Button("Accepter l’invitation") { Task { await model.accept() } }
                    .disabled(!model.canAccept).accessibilityIdentifier("join-confirm")
            } else {
                Button("Consulter l’invitation") { Task { await model.inspect() } }
                    .disabled(!model.canPreview).accessibilityIdentifier("join-preview")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
    }
}
