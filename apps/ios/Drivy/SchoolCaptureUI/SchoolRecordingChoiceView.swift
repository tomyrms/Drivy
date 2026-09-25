import SwiftUI

/// Injectable entry for a future school lesson sheet. No Root/Home/Report dependency.
struct SchoolRecordingChoiceEntryView: View {
    let client: SchoolCaptureClient
    let reader: any SchoolAPI
    let agenda: SchoolAgendaClient
    @Bindable var schoolWorkspace: SchoolWorkspace
    let lessonID: UUID
    let onRefusalConfirmed: @MainActor (UUID, UUID?) -> Void
    var store: SQLCipherSchoolCaptureStore? = nil
    @State private var model: SchoolRecordingChoiceWorkspace?
    @Environment(\.dismiss) private var dismiss

    private var currentScope: SchoolCommandScope? {
        guard let person = schoolWorkspace.person, let membership = schoolWorkspace.membership else { return nil }
        return .init(personID: person.personId, schoolID: membership.schoolId,
                     membershipID: membership.membershipId, accessEpoch: membership.accessEpoch,
                     apiBaseURL: client.baseURL.absoluteString)
    }
    private var scopeKey: String {
        "\(currentScope?.personID.uuidString ?? ""):\(currentScope?.membershipID.uuidString ?? ""):\(currentScope?.accessEpoch ?? 0):\(lessonID.uuidString)"
    }
    var body: some View {
        Group {
            if let model, model.scope == currentScope {
                SchoolRecordingChoiceView(model: model)
            } else {
                NavigationStack {
                    ContentUnavailableView("Choix GPS de la leçon", systemImage: "location.slash",
                        description: Text(currentScope == nil ? "Ouvrez une leçon de votre école pour retrouver ce choix." : "Vérification de la leçon…"))
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
                }
            }
        }
        .task(id: scopeKey) {
            model?.invalidate(); model = nil
            guard let scope = currentScope else { return }
            model = SchoolRecordingChoiceWorkspace(scope: scope, lessonID: lessonID,
                client: client, reader: reader, agenda: agenda, onRefusalConfirmed: onRefusalConfirmed, store: store)
        }
    }
}

struct SchoolRecordingChoiceView: View {
    @Bindable var model: SchoolRecordingChoiceWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: SchoolRecordingChoice.Status?
    @State private var review: ChoiceSheet?

    private enum ChoiceSheet: Identifiable {
        case new(SchoolRecordingChoiceReview)
        case resume(SchoolCaptureQueuedMutation)
        var id: UUID {
            switch self { case .new(let value): value.id; case .resume(let value): value.id }
        }
    }
    private var lessonDateLabel: String? {
        guard let lesson = model.lesson, let date = lesson.startsAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: lesson.timeZone) ?? .current
        formatter.dateStyle = .long; formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    heading
                    feedback
                    if let notice = model.notice {
                        currentChoice
                        RecordingNoticePanel(notice: notice)
                        if model.relatedPending.isEmpty && !model.accessRevoked { choiceControls }
                    }
                    if !model.relatedPending.isEmpty { pendingRequests }
                    if model.hasOldScope {
                        DrivyInlineMessage(text: "Une demande conservée relève de vos anciens accès. Elle ne sera pas renvoyée avec ces nouveaux droits.",
                            tone: .warning)
                    }
                    if !model.isLoading && !model.accessRevoked {
                        Button("Actualiser la notice et le choix", systemImage: "arrow.clockwise") { Task { await model.load() } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DrivyTheme.accent)
                            .frame(minHeight: 44).disabled(model.isBusy)
                    }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Choix GPS").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { await model.load() }
            .sheet(item: $review) { route in
                switch route {
                case .new(let value): RecordingChoiceConfirmation(model: model, review: value)
                case .resume(let value): RecordingChoiceRetry(model: model, queued: value)
                }
            }
            .onChange(of: model.notice?.noticeVersionId) { _, _ in selectedStatus = nil }
            .onChange(of: model.choice?.id) { _, _ in selectedStatus = nil }
            .onChange(of: model.accessRevoked) { _, revoked in if revoked { review = nil } }
        }
        .tint(DrivyTheme.accent).foregroundStyle(DrivyTheme.text)
        .interactiveDismissDisabled(model.isBusy)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyStatusBadge(title: "GPS facultatif", symbol: "location", tone: .accent)
            Text(model.source == .verbal ? "Le choix de l’élève" : "Votre choix pour cette leçon")
                .font(.drivyScreenTitle)
                .fixedSize(horizontal: false, vertical: true)
            if let learner = model.learner { Text(learner.displayName).font(.drivySection) }
            if let lessonDateLabel { Text(lessonDateLabel).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
            Text("La leçon peut se dérouler sans enregistrement GPS. Enregistrer ce choix ne démarre aucun trajet.")
                .font(.body).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private var feedback: some View {
        if model.isLoading { ProgressView("Lecture des informations de l’école…").frame(maxWidth: .infinity) }
        if let error = model.errorMessage { SchoolErrorNotice(message: error) }
        if let error = model.storageError { SchoolErrorNotice(message: error) }
        if let confirmation = model.confirmation {
            DrivyInlineMessage(text: confirmation)
        }
    }
    private var currentChoice: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text(model.needsReload ? "Dernier choix reçu" : "Choix communiqué à l’école").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                DrivyMapStatusLabel(status: DrivyMapStatus(title: model.currentChoiceLabel,
                    symbol: model.choice?.status == .allowed ? "location.fill" : model.choice?.status == .refused ? "location.slash" : "questionmark.circle",
                    tone: model.choice?.status == .allowed ? .success : .neutral), font: .headline)
                    .accessibilityIdentifier("recording-current-choice")
                if let choice = model.choice {
                    Text(choice.source == .own ? "Exprimé par l’élève depuis son compte" : "Choix verbal consigné par un moniteur")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    if choice.lessonId == nil { Text("Ce choix s’applique actuellement à cette leçon.").font(.caption).foregroundStyle(DrivyTheme.muted) }
                    if choice.noticeVersionId != model.notice?.noticeVersionId {
                        DrivyInlineMessage(text: "La notice a changé depuis ce choix. Un accord lié à l’ancienne notice n’autorise pas un nouveau départ GPS.",
                            tone: .warning)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var choiceControls: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            Text(model.source == .verbal ? "Quel choix l’élève a-t-il exprimé ?" : "Pour cette leçon")
                .font(.drivySection)
                .accessibilityAddTraits(.isHeader)
            choiceButton(.refused, title: "Sans enregistrement GPS", detail: model.source == .verbal ? "L’élève a exprimé son refus." : "Je ne souhaite pas enregistrer le trajet.", symbol: "location.slash")
            choiceButton(.allowed, title: "Avec enregistrement GPS", detail: model.source == .verbal ? "L’élève a exprimé son accord après avoir reçu l’information." : "J’accepte l’enregistrement décrit dans la notice.", symbol: "location")
            if model.verbalAgreementIsProtected {
                Text("L’élève a exprimé son refus depuis son compte. Lui seul peut revenir sur ce choix.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            Button {
                if let selectedStatus, let value = model.review(selectedStatus) { review = .new(value) }
            } label: { Label("Relire mon choix", systemImage: "checklist") }
                .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.mayChoose || selectedStatus == nil)
                .accessibilityIdentifier("recording-review-choice")
        }
    }
    private func choiceButton(_ status: SchoolRecordingChoice.Status, title: String, detail: String, symbol: String) -> some View {
        Button { selectedStatus = status } label: {
            HStack(alignment: .top, spacing: DrivySpacing.s) {
                Image(systemName: symbol).font(.title3).frame(width: 28).foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                DrivySelectionMark(isSelected: selectedStatus == status)
            }
        }
        .buttonStyle(DrivySelectionCardStyle(isSelected: selectedStatus == status))
        .disabled(!model.mayChoose || (status == .allowed && model.verbalAgreementIsProtected))
        .accessibilityAddTraits(selectedStatus == status ? .isSelected : [])
        .accessibilityIdentifier(status == .allowed ? "recording-allow" : "recording-refuse")
    }
    private var pendingRequests: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            Text("Confirmation à retrouver").font(.drivySection).accessibilityAddTraits(.isHeader)
            Text("Une demande est conservée sur cet appareil. Vérifiez son résultat avant d’en créer une autre pour cet élève.")
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            ForEach(model.relatedPending) { queued in
                DrivyPanel {
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        RecordingPendingDescription(command: queued.mutation)
                        if queued.mutation.scope == model.scope {
                            Button("Vérifier auprès de l’école") { Task { await model.verify(queued) } }
                                .buttonStyle(DrivySecondaryButtonStyle()).disabled(!model.mayResume(queued))
                            Button("Relire et renvoyer la même demande") { review = .resume(queued) }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.accent)
                                .frame(minHeight: 44).disabled(!model.mayResume(queued))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct RecordingNoticePanel: View {
    let notice: SchoolRecordingNotice
    var body: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                Text("L’information de votre école").font(.drivySection).accessibilityAddTraits(.isHeader)
                Text(notice.noticeText).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(DrivyTheme.border)
                Text("Conservation des données").font(.headline)
                Text(notice.retentionText).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Label(notice.contactEmail, systemImage: "envelope").font(.subheadline).textSelection(.enabled)
                    .foregroundStyle(DrivyTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecordingChoiceConfirmation: View {
    @Bindable var model: SchoolRecordingChoiceWorkspace
    let review: SchoolRecordingChoiceReview
    @State private var acknowledged = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Text(review.status == .allowed ? "Confirmer l’accord GPS" : "Confirmer le choix sans GPS").font(.drivyTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(review.learnerName).font(.drivySection)
                    }
                    RecordingNoticePanel(notice: review.notice)
                    Toggle(isOn: $acknowledged) {
                        Text(review.source == .own
                             ? "J’ai lu cette notice et je confirme mon choix pour cette leçon."
                             : "J’ai présenté cette notice à l’élève et je retranscris le choix qu’il a exprimé.")
                            .fixedSize(horizontal: false, vertical: true)
                    }.disabled(model.isBusy)
                    Label("Aucun trajet ne démarre avec cette confirmation.", systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = model.errorMessage { SchoolErrorNotice(message: error) }
                    Button {
                        Task { if await model.confirm(review, acknowledged: acknowledged) { dismiss() } }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isBusy { ProgressView() }
                            Text(model.isBusy ? "Enregistrement du choix…" : "Enregistrer ce choix")
                        }
                    }.buttonStyle(DrivyPrimaryButtonStyle()).disabled(!acknowledged || !model.mayChoose)
                        .accessibilityIdentifier("recording-confirm-choice")
                }.drivyPageContent()
            }
            .background(DrivyTheme.surface).navigationTitle("Votre confirmation").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { dismiss() }.disabled(model.isBusy) } }
        }.tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
    }
}

private struct RecordingPendingDescription: View {
    let command: SchoolCapturePendingMutation
    private var bodyValue: SchoolRecordingChoiceBody? { try? JSONDecoder().decode(SchoolRecordingChoiceBody.self, from: command.body) }
    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            if let value = bodyValue {
                Text(value.status == .allowed ? "Demande d’accord GPS" : value.status == .refused ? "Demande de choix sans GPS" : "Choix non renseigné à confirmer").font(.headline)
                Text(value.source == .own ? "Choix personnel de l’élève" : "Choix verbal consigné par un moniteur").font(.subheadline)
                Text(value.lessonId == nil ? "Choix général de cet élève" : "Choix pour une leçon").font(.caption).foregroundStyle(DrivyTheme.muted)
            }
            DisclosureGroup("Référence de la demande") {
                Text(command.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
            }.font(.subheadline)
        }
    }
}

private struct RecordingChoiceRetry: View {
    @Bindable var model: SchoolRecordingChoiceWorkspace
    let queued: SchoolCaptureQueuedMutation
    @State private var acknowledged = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    Text("Retrouver la confirmation").font(.drivyTitle)
                    RecordingPendingDescription(command: queued.mutation)
                    Text("Le contenu et la notice liés à cette demande restent ceux de votre confirmation initiale. Le renvoi utilise la même référence ; il ne crée pas un nouveau choix.")
                        .foregroundStyle(DrivyTheme.muted)
                    Toggle("Je souhaite renvoyer exactement cette demande.", isOn: $acknowledged).disabled(model.isBusy)
                    if let error = model.errorMessage { SchoolErrorNotice(message: error) }
                    Button {
                        Task { if await model.resend(queued, acknowledged: acknowledged) { dismiss() } }
                    } label: { Text("Renvoyer la même demande") }
                        .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!acknowledged || !model.mayResume(queued))
                }.drivyPageContent()
            }.background(DrivyTheme.surface)
            .navigationTitle("Demande conservée").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
        }.tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
    }
}
