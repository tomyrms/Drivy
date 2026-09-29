import SwiftUI

struct SchoolCaptureHistoryView: View {
    @Bindable var model: SchoolCaptureHistoryWorkspace
    @Bindable var workspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var partialCapture: SchoolCaptureStoredSession?
    @State private var replay: ReplayRoute?

    private struct ReplayRoute: Identifiable {
        let model: SchoolCaptureReplayWorkspace
        let learnerName: String
        var id: UUID { model.id }
    }

    private var currentScope: SchoolCommandScope? {
        guard let person = workspace.person, let member = workspace.membership else { return nil }
        return SchoolCommandScope(personID: person.personId, schoolID: member.schoolId,
            membershipID: member.membershipId, accessEpoch: member.accessEpoch, apiBaseURL: model.client.baseURL.absoluteString)
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section {
                        SchoolErrorNotice(message: error,
                            retry: model.accessRevoked || model.isBusy ? nil : { Task { await model.load() } })
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if let feedback = model.feedback {
                    Section { DrivyInlineMessage(text: feedback, tone: .neutral) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if model.isLoading && model.captures.isEmpty {
                    ProgressView("Ouverture des trajets…").frame(maxWidth: .infinity)
                } else if model.captures.isEmpty && model.errorMessage == nil {
                    ContentUnavailableView("Aucun trajet terminé", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("Les trajets GPS de cette école conservés sur cet appareil apparaîtront ici après leur arrêt."))
                }
                ForEach(model.captures) { capture in
                    Section {
                        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                            Text(learnerName(capture)).font(.headline).foregroundStyle(DrivyTheme.text)
                            if let date = SchoolLesson.date(capture.serverCapture.authorizedAt) {
                                Text(date, format: .dateTime.weekday(.abbreviated).day().month(.wide).hour().minute())
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }
                            DrivyMapStatusLabel(status: DrivyMapStatus(title: status(capture), symbol: symbol(capture), tone: tone(capture)),
                                font: .subheadline.weight(.semibold))
                            let count = capture.manifest?.reduce(0) { $0 + $1.expectedPointCount } ?? 0
                            Text("\(count) position\(count == 1 ? "" : "s") conservée\(count == 1 ? "" : "s") sur cet appareil")
                                .font(.footnote.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                            if capture.state == .interrupted {
                                Label("L’enregistrement a été interrompu. Le GPS n’a pas été relancé.", systemImage: "exclamationmark.triangle")
                                    .font(.footnote).foregroundStyle(DrivyTheme.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if model.busyCaptureID == capture.id { ProgressView("Échange avec l’école…") }
                        }.padding(.vertical, DrivySpacing.xxs)
                        .accessibilityElement(children: .combine)
                        if isReplayable(capture) {
                            Button("Revoir le trajet", systemImage: "play.circle") {
                                replay = ReplayRoute(model: SchoolCaptureReplayWorkspace(scope: model.scope, client: model.client, captureID: capture.id),
                                                     learnerName: learnerName(capture))
                            }
                            .disabled(model.isBusy)
                            .accessibilityHint("Carte, chronologie et observations privées de ce trajet")
                            .accessibilityIdentifier("school-history-replay-\(capture.id.uuidString)")
                        }
                        if model.maySend(capture) || model.busyCaptureID == capture.id {
                            if let allowPartial = model.pendingFinalization[capture.id] {
                                Button("Reprendre la confirmation", systemImage: "arrow.clockwise") {
                                    Task { await model.finalize(capture, allowPartial: allowPartial) }
                                }.disabled(model.isBusy)
                                Text(allowPartial ? "Clôture partielle déjà demandée : la même demande sera renvoyée."
                                    : "Trajet complet déjà demandé : la même demande sera renvoyée.")
                                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
                            } else {
                            Button("Envoyer les données conservées", systemImage: "arrow.up.circle") {
                                Task { await model.send(capture) }
                            }.disabled(model.isBusy)
                            Button("Vérifier le trajet complet", systemImage: "checkmark.circle") {
                                Task { await model.finalize(capture, allowPartial: false) }
                            }.disabled(model.isBusy)
                            Button("Autoriser un trajet partiel…") { partialCapture = capture }.disabled(model.isBusy)
                            }
                        }
                    }
                }
                Section {
                    Text("Ces trajets restent privés. Leur envoi ne publie aucun bilan et ne redémarre pas le GPS.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle("Trajets de l’école").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .refreshable { await model.load() }
            .task { await model.load() }
            .onChange(of: currentScope) { _, scope in
                if scope != model.scope { replay?.model.invalidate(); replay = nil; model.invalidate(); dismiss() }
            }
            .fullScreenCover(item: $replay) { route in
                SchoolCaptureReplayView(model: route.model, learnerName: route.learnerName)
            }
            .confirmationDialog("Autoriser un trajet partiel ?", isPresented: confirmsPartial, titleVisibility: .visible,
                presenting: partialCapture) { capture in
                Button("Autoriser la clôture partielle") { Task { await model.finalize(capture, allowPartial: true) } }
                Button("Annuler", role: .cancel) { }
            } message: { _ in
                Text("Seules les positions confirmées par l’école seront retenues. Les lacunes resteront visibles et le trajet ne sera pas publié.")
            }
        }.tint(DrivyTheme.accent)
    }

    /// Only a private capture the school has reconstructed (complete or partial) has a replay.
    private func isReplayable(_ capture: SchoolCaptureStoredSession) -> Bool {
        !model.accessRevoked && capture.serverCapture.publicationState == .privateCapture
            && [SchoolCaptureSession.SyncState.synced, .partial].contains(capture.serverCapture.syncState)
    }

    private var confirmsPartial: Binding<Bool> {
        Binding(get: { partialCapture != nil }, set: { if !$0 { partialCapture = nil } })
    }
    private func learnerName(_ capture: SchoolCaptureStoredSession) -> String {
        if workspace.learner?.id == capture.serverCapture.learnerId { return workspace.learner?.displayName ?? "Trajet de leçon" }
        return workspace.learners.first { $0.id == capture.serverCapture.learnerId }?.displayName ?? "Trajet de leçon"
    }
    private func status(_ capture: SchoolCaptureStoredSession) -> String {
        if capture.serverCapture.publicationState == .withdrawn { return "Trajet retiré" }
        if capture.serverCapture.publicationState == .deleted { return "Trajet supprimé" }
        switch capture.serverCapture.syncState {
        case .synced: return "Synchronisé · privé"
        case .partial: return model.confirmedFinalization[capture.id] == nil ? "Positions manquantes · à vérifier" : "Partiel · privé"
        case .rejected: return "Envoi refusé"
        case .localOnly, .uploading:
            return (model.pendingCount[capture.id] ?? 0) > 0 ? "Des données restent à envoyer" : "Prêt à vérifier"
        }
    }
    private func symbol(_ capture: SchoolCaptureStoredSession) -> String {
        switch capture.serverCapture.publicationState {
        case .withdrawn, .deleted: return "minus.circle"
        default: break
        }
        switch capture.serverCapture.syncState {
        case .synced: return "checkmark.circle"
        case .partial, .rejected: return "exclamationmark.circle"
        case .localOnly, .uploading: return "iphone.and.arrow.forward"
        }
    }
    /// Transfer pending is information, not an alert; only a gap or a refusal asks for attention.
    private func tone(_ capture: SchoolCaptureStoredSession) -> DrivyTone {
        switch capture.serverCapture.publicationState {
        case .withdrawn, .deleted: return .neutral
        default: break
        }
        switch capture.serverCapture.syncState {
        case .synced: return .success
        case .partial, .rejected: return .warning
        case .localOnly, .uploading: return (model.pendingCount[capture.id] ?? 0) > 0 ? .accent : .neutral
        }
    }
}
