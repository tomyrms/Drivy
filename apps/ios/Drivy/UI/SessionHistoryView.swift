import SwiftUI

struct SessionHistoryView: View {
    @Bindable var controller: SessionController

    private var sessions: [DrivingSession] {
        controller.sessions
            .filter { $0.state != .active }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        Group {
            if controller.isLoading {
                ProgressView("Ouverture des trajets…")
            } else if sessions.isEmpty, let error = controller.errorMessage {
                ContentUnavailableView {
                    Label("Historique indisponible", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    if !controller.isCapturing && !controller.isBusy {
                        Button("Réessayer") { Task { await controller.load() } }
                            .buttonStyle(.bordered)
                    }
                }
            } else if sessions.isEmpty {
                ContentUnavailableView {
                    Label("Aucun trajet terminé", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Les trajets terminés et leurs bilans personnels apparaîtront ici.")
                }
            } else {
                List {
                    if !sessions.filter({ !$0.isExample }).isEmpty {
                        Section("Sur cet appareil") {
                            ForEach(sessions.filter { !$0.isExample }) { session in
                                NavigationLink(value: session.id) {
                                    SessionHistoryRow(session: session)
                                }
                                .accessibilityIdentifier("history-session-\(session.id.uuidString)")
                            }
                        }
                    }
                    if !sessions.filter(\.isExample).isEmpty {
                        Section {
                            ForEach(sessions.filter(\.isExample)) { session in
                                NavigationLink(value: session.id) { SessionHistoryRow(session: session) }
                                    .accessibilityIdentifier("history-session-\(session.id.uuidString)")
                            }
                        } header: {
                            Text("Trajets d’exemple")
                        } footer: {
                            Text("Tracés, horaires et observations fictifs pour découvrir le replay.")
                        }
                    }
                    if let error = controller.errorMessage {
                        Section { InlineErrorView(message: error) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Historique")
    }
}

private struct SessionHistoryRow: View {
    let session: DrivingSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: session.usesGPS || !session.points.isEmpty ? "point.topleft.down.to.point.bottomright.curvepath" : "note.text")
                    .font(.body)
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let title = session.title { Text(title).font(.headline) }
                else { Text(session.startedAt, format: .dateTime.day().month(.wide).hour().minute()).font(.headline) }
                Text(session.isExample ? "Exemple · données fictives" : session.state.label)
                    .font(.subheadline)
                    .foregroundStyle(session.state == .interrupted ? DrivyTheme.warning : DrivyTheme.muted)
                Text("\(session.observations.count) observation\(session.observations.count == 1 ? "" : "s") · \(session.isExample ? "Replay" : session.usesGPS ? "Avec GPS" : "Sans GPS")")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct SummaryEditorView: View {
    @Bindable var controller: SessionController
    let sessionID: UUID
    let initialText: String
    let isExample: Bool
    @State private var text: String
    @State private var saving = false
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(controller: SessionController, sessionID: UUID, initialText: String, isExample: Bool = false) {
        self.controller = controller
        self.sessionID = sessionID
        self.initialText = initialText
        self.isExample = isExample
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isExample {
                        Label("Bilan d’exemple · contenu fictif", systemImage: "info.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DrivyTheme.muted)
                    }
                    Text("Notes du trajet")
                        .font(.headline)
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Texte du bilan personnel")
                        .accessibilityIdentifier("summary-text")
                        .disabled(saving)
                    if text.count > 10_000 {
                        Text("Limitez le bilan à 10 000 caractères pour l’enregistrer.")
                            .font(.footnote)
                            .foregroundStyle(DrivyTheme.danger)
                    }
                    if let error = controller.errorMessage {
                        InlineErrorView(message: error)
                    }
                    if saving {
                        ProgressView("Enregistrement…")
                    }
                    Text("Ce bilan reste sur cet appareil. Il n’est pas partagé avec l’école.")
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("Bilan personnel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if text == initialText { dismiss() } else { confirmsDiscard = true }
                    }
                    .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(saving || text.count > 10_000)
                        .accessibilityIdentifier("save-summary")
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(saving || text != initialText)
        .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmsDiscard) {
            Button("Abandonner les modifications", role: .destructive) { dismiss() }
            Button("Continuer la rédaction", role: .cancel) { }
        } message: {
            Text("Les modifications depuis l’ouverture de ce bilan ne sont pas enregistrées.")
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            let saved = await controller.updateSummary(text, for: sessionID)
            saving = false
            if saved { dismiss() }
        }
    }
}
