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
                    heading
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
    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: model.isConfirmed ? "checkmark.seal" : "envelope.open")
                .font(.title).foregroundStyle(DrivyTheme.accent)
                .frame(width: 64, height: 64).background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            Text(model.isConfirmed ? "Bienvenue dans votre école" : "Votre école vous invite")
                .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            if model.preview == nil {
                Text("Ouvrez l’invitation reçue avec le compte correspondant à son adresse destinataire.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
        }
    }
    private var linkEntry: some View {
        VStack(alignment: .leading, spacing: 18) {
            DrivyPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Lien d’invitation").font(.headline)
                    SecureField("Coller le lien reçu", text: $model.link)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).onSubmit { Task { await model.inspect() } }
                        .accessibilityIdentifier("join-invitation-link")
                    PasteButton(payloadType: String.self) { values in
                        if let value = values.first, value.utf8.count <= 2_048 { model.link = value }
                    }
                    .disabled(model.isBusy || !model.isReady)
                }
            }
            Button { Task { await model.inspect() } } label: {
                Text("Consulter l’invitation").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).disabled(!model.canPreview)
            .accessibilityIdentifier("join-preview")
            Text("Cette étape affiche l’école et sa notice avant toute acceptation.")
                .font(.footnote).foregroundStyle(DrivyTheme.muted)
        }
    }
    private func invitation(_ preview: SchoolJoinPreview) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            schoolCard(preview)
            VStack(alignment: .leading, spacing: 14) {
                Text("Vos données dans l’école").font(.title2.bold())
                Text("Notice · version \(preview.notice.version)").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                DrivyPanel {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(preview.notice.noticeText).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        DisclosureGroup("Conservation des données", isExpanded: $expandsRetention) {
                            Text(preview.notice.retentionText).textSelection(.enabled).padding(.top, 12)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Contact de l’école").font(.caption).foregroundStyle(DrivyTheme.muted)
                            Text(preview.notice.contactEmail).textSelection(.enabled)
                        }
                    }
                }
            }
            Toggle(isOn: $model.acknowledgesNotice) {
                Text("J’ai pris connaissance de cette notice et je souhaite rejoindre l’école avec les rôles affichés.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18).background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .disabled(model.isBusy)
            .accessibilityIdentifier("join-acknowledge")
            Button { Task { await model.accept() } } label: {
                Text("Accepter l’invitation").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).disabled(!model.canAccept)
            .accessibilityIdentifier("join-confirm")
            Button("Utiliser un autre lien") { model.anotherInvitation() }.frame(minHeight: 48).disabled(model.isBusy)
        }
    }
    private func schoolCard(_ preview: SchoolJoinPreview) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(preview.schoolName).font(.title2.bold())
                Label(SchoolPresentation.roles(preview.roles), systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(DrivyTheme.accent)
                Label(preview.maskedEmail, systemImage: "envelope").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                if !model.isConfirmed {
                    Text("Invitation valable jusqu’au \(SchoolTrainingFormatting.instant(preview.expiresAt, zone: TimeZone.current.identifier))")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var pending: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let preview = model.preview { schoolCard(preview) }
            DrivyPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Confirmation à vérifier", systemImage: "clock.arrow.circlepath").font(.headline)
                    Text("Votre demande est conservée sur cet appareil. Vous pouvez fermer cet écran et revenir la vérifier avec ce compte.")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    if let record = model.record { Text(record.operationID.uuidString).font(.caption.monospaced()).textSelection(.enabled) }
                    Button("Vérifier la confirmation") { Task { await model.verify() } }.frame(minHeight: 48)
                    Button("Renvoyer la même demande") { Task { await model.retry() } }.frame(minHeight: 48)
                }
            }.disabled(model.isBusy)
        }
    }
    private var confirmed: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let preview = model.preview { schoolCard(preview) }
            Label("Votre invitation a été acceptée.", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(DrivyTheme.accent)
            if let member = model.member {
                Text("Accès actuel : \(SchoolPresentation.roles(member.roles))")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                Button { openSchool(member) } label: {
                    Text("Ouvrir mon école").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(model.isBusy)
            } else {
                Text("La confirmation est conservée. Actualisez vos accès pour ouvrir l’école.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                Button("Actualiser mes accès") { Task { await model.verify() } }.frame(minHeight: 48).disabled(model.isBusy)
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
}
