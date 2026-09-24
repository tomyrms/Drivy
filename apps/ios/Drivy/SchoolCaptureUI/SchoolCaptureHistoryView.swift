import SwiftUI

struct SchoolCaptureHistoryView: View {
    @Bindable var model: SchoolCaptureHistoryWorkspace
    @Bindable var workspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var partialCapture: SchoolCaptureStoredSession?

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
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(DrivyTheme.warning)
                        if !model.accessRevoked { Button("Réessayer") { Task { await model.load() } }.disabled(model.isBusy) }
                    }
                }
                if let feedback = model.feedback {
                    Section { Text(feedback).foregroundStyle(DrivyTheme.muted) }
                }
                if model.isLoading && model.captures.isEmpty {
                    ProgressView("Ouverture des trajets…")
                } else if model.captures.isEmpty && model.errorMessage == nil {
                    ContentUnavailableView("Aucun trajet terminé", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("Les trajets GPS de cette école conservés sur cet appareil apparaîtront ici après leur arrêt."))
                }
                ForEach(model.captures) { capture in
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(learnerName(capture)).font(.headline)
                            if let date = SchoolLesson.date(capture.serverCapture.authorizedAt) {
                                Text(date, format: .dateTime.day().month(.wide).hour().minute())
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }
                            Label(status(capture), systemImage: symbol(capture))
                                .font(.subheadline)
                            let count = capture.manifest?.reduce(0) { $0 + $1.expectedPointCount } ?? 0
                            Text("\(count) position\(count == 1 ? "" : "s") conservée\(count == 1 ? "" : "s") sur cet appareil")
                                .font(.footnote).foregroundStyle(DrivyTheme.muted)
                            if capture.state == .interrupted {
                                Text("L’enregistrement a été interrompu. Le GPS n’a pas été relancé.")
                                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
                            }
                            if model.busyCaptureID == capture.id { ProgressView("Échange avec l’école…") }
                        }.padding(.vertical, 6)
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
            .navigationTitle("Trajets de l’école").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .refreshable { await model.load() }
            .task { await model.load() }
            .onChange(of: currentScope) { _, scope in
                if scope != model.scope { model.invalidate(); dismiss() }
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
        switch capture.serverCapture.syncState {
        case .synced: "checkmark.circle"
        case .partial, .rejected: "exclamationmark.circle"
        case .localOnly, .uploading: "iphone.and.arrow.forward"
        }
    }
}
