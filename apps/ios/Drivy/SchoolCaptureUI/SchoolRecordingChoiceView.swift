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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    ScrollView {
                        ContentUnavailableView("Choix GPS de la leçon", systemImage: "location.slash",
                            description: Text(currentScope == nil ? "Ouvre une leçon de ton école pour retrouver ce choix." : "Vérification de la leçon…"))
                            .fixedSize(horizontal: false, vertical: true)
                            .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
                }
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationSizing(.form)
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
    @State private var document: RecordingDocument?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if let learner = model.learner {
                        Text(learner.displayName).font(.drivyTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.isLoading && model.notice == nil {
                        DrivySkeletonRows(count: 2)
                            .drivySkeleton("Chargement du choix…")
                    }
                    if let error = model.errorMessage {
                        SchoolErrorNotice(message: error,
                            retry: model.accessRevoked || model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
                    }
                    if let error = model.storageError { SchoolErrorNotice(message: error) }
                    if model.notice != nil, !model.accessRevoked {
                        if model.relatedPending.isEmpty { choiceControls }
                        else { pendingRequests }
                    }
                    if model.hasOldScope {
                        DrivyInlineMessage(text: "Une demande dépend de tes anciens accès. Reconnecte-toi au compte d’origine pour la retrouver.", tone: .warning)
                    }
                    if let notice = model.notice { documentLinks(notice) }
                }
                .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(DrivyTheme.surface)
            .navigationTitle("Accord GPS").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(model.isBusy) }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(item: $document) { RecordingDocumentView(document: $0) }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .tint(DrivyTheme.accent).foregroundStyle(DrivyTheme.text)
        .interactiveDismissDisabled(model.isBusy)
    }

    private var choiceControls: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            Text(model.source == .verbal ? "L’élève accepte-t-il le GPS ?" : "Acceptes-tu le GPS ?")
                .font(.drivySection).accessibilityAddTraits(.isHeader)
            if model.choice?.status != .unknown, model.choice != nil {
                Text(model.currentChoiceLabel).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .accessibilityIdentifier("recording-current-choice")
            }
            // Deux cartes de même taille, même poids, même teinte : aucune réponse n’est mise en avant.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DrivySpacing.s))
                : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
            layout {
                choiceButton(.allowed, title: "Avec GPS", symbol: "location.fill")
                choiceButton(.refused, title: "Sans GPS", symbol: "location.slash")
            }
            if model.isBusy { DrivyLoadingState(title: "Enregistrement du choix…") }
            if model.verbalAgreementIsProtected {
                DrivyInlineMessage(text: "L’élève a refusé depuis son compte. Lui seul peut modifier ce choix.", tone: .warning)
            }
        }
    }

    private func choiceButton(_ status: SchoolRecordingChoice.Status, title: String, symbol: String) -> some View {
        let isEnabled = model.mayChoose && !(status == .allowed && model.verbalAgreementIsProtected)
        return Button {
            Task { if await model.choose(status) { dismiss() } }
        } label: {
            // Motif unique de sélection : les deux réponses ont le même poids (aucun biais vers
            // l’accord) et le choix déjà enregistré se lit à la coche, pas à la couleur seule.
            let isChosen = model.choice?.status == status
            VStack(spacing: DrivySpacing.s) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isEnabled ? DrivyTheme.accent : DrivyTheme.disabledText)
                    .frame(width: 44, height: 44)
                    .background(isChosen ? DrivyTheme.surface : DrivyTheme.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                HStack(spacing: DrivySpacing.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isEnabled ? DrivyTheme.text : DrivyTheme.disabledText)
                        .fixedSize(horizontal: false, vertical: true)
                    DrivySelectionMark(isSelected: isChosen)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104)
        }
        .buttonStyle(DrivySelectionCardStyle(isSelected: model.choice?.status == status))
        .disabled(!isEnabled)
        .accessibilityAddTraits(model.choice?.status == status ? .isSelected : [])
        .accessibilityHint(status == .allowed ? "Enregistrer l’accord et continuer" : "Enregistrer le refus et continuer sans GPS")
        .accessibilityIdentifier(status == .allowed ? "recording-allow" : "recording-refuse")
    }

    private func documentLinks(_ notice: SchoolRecordingNotice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Informations de ton école") {
                document = .init(id: "notice", title: "Informations de ton école", text: notice.noticeText, contact: notice.contactEmail)
            }
            .accessibilityIdentifier("recording-notice-link")
            .frame(minHeight: 44)
            Button("Conservation des données") {
                document = .init(id: "retention", title: "Conservation des données", text: notice.retentionText, contact: notice.contactEmail)
            }
            .accessibilityIdentifier("recording-retention-link")
            .frame(minHeight: 44)
        }
        .font(.subheadline).foregroundStyle(DrivyTheme.accent)
    }

    private var pendingRequests: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            DrivyInlineMessage(text: "Le choix est conservé sur cet appareil. Son enregistrement par l’école reste à vérifier.", tone: .warning)
            ForEach(model.relatedPending) { queued in
                if queued.mutation.scope == model.scope {
                    Button("Réessayer") {
                        Task { if await model.resend(queued, acknowledged: true) { dismiss() } }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle(size: .field)).disabled(!model.mayResume(queued))
                    if model.unknownRequestIDs.contains(queued.id) {
                        DrivyInlineMessage(text: "L’école n’a pas reçu ce choix : rien n’a été enregistré.", tone: .warning)
                        Button("Abandonner la demande", role: .destructive) { Task { await model.abandon(queued) } }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.danger)
                            .frame(minHeight: 44).disabled(!model.mayResume(queued))
                    } else {
                        Button("Vérifier auprès de l’école") { Task { await model.verify(queued) } }
                            .buttonStyle(DrivySecondaryButtonStyle()).disabled(!model.mayResume(queued))
                    }
                }
            }
        }
    }
}

private struct RecordingDocument: Identifiable {
    let id: String
    let title: String
    let text: String
    let contact: String
}

private struct RecordingDocumentView: View {
    let document: RecordingDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    Text(document.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(document.contact, systemImage: "envelope").font(.footnote)
                        .foregroundStyle(DrivyTheme.muted).textSelection(.enabled)
                }.drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }.tint(DrivyTheme.accent)
    }
}
