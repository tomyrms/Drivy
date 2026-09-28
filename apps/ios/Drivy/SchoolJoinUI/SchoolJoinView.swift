import SwiftUI

struct SchoolJoinView: View {
    @Bindable var model: SchoolJoinWorkspace
    let openSchool: (SchoolMembership) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var expandsRetention = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.isBusy { ProgressView("Vérification auprès de l’école…") }
                    if let error = model.errorMessage {
                        SchoolErrorNotice(message: error)
                        if !model.isReady { Button("Réessayer") { Task { await model.load() } }.frame(minHeight: 48) }
                    }
                    if model.isConfirmed { confirmed }
                    else if model.isPending { pending }
                    else if let preview = model.preview { invitation(preview) }
                    else { linkEntry }
                }
                .padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
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
        VStack(alignment: .leading, spacing: 18) {
            Text("Lien d’invitation").font(.title2.bold())
            Text("Utilisez le compte correspondant à l’adresse destinataire de l’invitation.")
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            SecureField("Coller le lien reçu", text: $model.link)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).onSubmit { Task { await model.inspect() } }
                .padding(16).background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .disabled(model.isBusy || !model.isReady)
                .accessibilityIdentifier("join-invitation-link")
            PasteButton(payloadType: String.self) { values in
                if let value = values.first, value.utf8.count <= 2_048 { model.link = value }
            }
            .disabled(model.isBusy || !model.isReady)
            Text("Vous relirez l’école, les rôles et la notice avant d’accepter.")
                .font(.footnote).foregroundStyle(DrivyTheme.muted)
        }
    }
    private func invitation(_ preview: SchoolJoinPreview) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            schoolSummary(preview)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Vos données dans l’école").font(.title2.bold())
                Text("Notice · version \(preview.notice.version)").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                Text(preview.notice.noticeText).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Conservation des données", isExpanded: $expandsRetention) {
                    Text(preview.notice.retentionText).textSelection(.enabled).padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Contact de l’école").font(.caption).foregroundStyle(DrivyTheme.muted)
                    Text(preview.notice.contactEmail).textSelection(.enabled)
                }
            }
            Divider()
            Toggle(isOn: $model.acknowledgesNotice) {
                Text("J’ai pris connaissance de cette notice et je souhaite rejoindre l’école avec les rôles affichés.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("join-acknowledge")
            Button("Utiliser un autre lien") { model.anotherInvitation() }.frame(minHeight: 48).disabled(model.isBusy)
        }
    }
    private func schoolSummary(_ preview: SchoolJoinPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.schoolName).font(.title.bold())
            Label(SchoolPresentation.roles(preview.roles), systemImage: "person.crop.circle")
                .font(.subheadline.weight(.medium)).foregroundStyle(DrivyTheme.accent)
            Label(preview.maskedEmail, systemImage: "envelope").font(.subheadline).foregroundStyle(DrivyTheme.muted)
            if !model.isConfirmed {
                Text("Invitation valable jusqu’au \(SchoolTrainingFormatting.instant(preview.expiresAt, zone: TimeZone.current.identifier))")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var pending: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let preview = model.preview { schoolSummary(preview) }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Label("Confirmation à vérifier", systemImage: "clock.arrow.circlepath").font(.headline)
                Text("Votre demande est conservée sur cet appareil. Vous pouvez fermer cet écran et revenir la vérifier avec ce compte.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                if let record = model.record {
                    DisclosureGroup("Référence de la demande") {
                        Text(record.operationID.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Button("Renvoyer la même demande") { Task { await model.retry() } }.frame(minHeight: 48)
            }.disabled(model.isBusy)
        }
    }
    private var confirmed: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let preview = model.preview { schoolSummary(preview) }
            Label("Votre invitation a été acceptée.", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(DrivyTheme.success)
            if let member = model.member {
                Text("Accès actuel : \(SchoolPresentation.roles(member.roles))")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            } else {
                Text("La confirmation est conservée. Actualisez vos accès pour ouvrir l’école.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            if let receipt = model.record?.receipt {
                DisclosureGroup("Confirmation enregistrée") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(receipt.operationId.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                        Text(SchoolTrainingFormatting.instant(receipt.committedAt, zone: TimeZone.current.identifier)).font(.caption)
                    }.padding(.top, 10)
                }.font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            Button("Une autre invitation") { model.anotherInvitation() }.frame(minHeight: 48).disabled(model.isBusy)
        }
    }
    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.errorMessage, model.preview != nil {
                Text(error).font(.footnote).foregroundStyle(DrivyTheme.danger)
            } else if model.preview != nil && !model.isConfirmed && !model.isPending && !model.acknowledgesNotice && !model.isBusy {
                Text("Confirmez votre lecture de la notice pour accepter.").font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
            if model.isConfirmed {
                if let member = model.member {
                    Button("Ouvrir mon école") { openSchool(member) }.disabled(model.isBusy)
                } else {
                    Button("Actualiser mes accès") { Task { await model.verify() } }.disabled(model.isBusy)
                }
            } else if model.isPending {
                Button("Vérifier la confirmation") { Task { await model.verify() } }.disabled(model.isBusy)
            } else if model.preview != nil {
                Button("Accepter l’invitation") { Task { await model.accept() } }
                    .disabled(!model.canAccept).accessibilityIdentifier("join-confirm")
            } else {
                Button("Consulter l’invitation") { Task { await model.inspect() } }
                    .disabled(!model.canPreview).accessibilityIdentifier("join-preview")
            }
        }.buttonStyle(DrivyPrimaryButtonStyle())
            .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity).background(DrivyTheme.surface)
    }
}
